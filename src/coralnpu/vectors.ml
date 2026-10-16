[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type write = { cycle : int; port : int; pc : int option; reg : int; strobe : Bits.t; data : Bits.t }

type summary = {
  cycles : int;
  relations : (string * int * int) list;
  failures : Diag.t list;
  storage : (int * Bits.t) list;
  storage_at : (int * (int * Bits.t) list) option;
}

let model = "vectors"
let needs = "v_registers" :: Commits.needs
let code = "vectors.storage"
let retired_code = "vectors.retired"
let byte b i = Bits.field_int b ~lo:(8 * i) ~width:8

(* Byte [i] of the result is [f i]; byte 0 is the least significant. *)
let of_bytes n f = Bits.concat (List.init n (fun k -> Bits.of_int ~width:8 (f (n - 1 - k))))

let of_bits n f =
  Bits.concat (List.init n (fun k -> Bits.of_int ~width:1 (if f (n - 1 - k) then 1 else 0)))

(* A replayed register: which bytes have been written, and their values. *)
type written = { known : Bits.t; value : Bits.t }

let graph ?at (c : _ Core.t) f =
  let v = Core.block c "v_registers" c.platform.blocks.v_registers in
  let sc = Core.scope c v.vr_scope in
  let commits, _ = Commits.events c in
  let n = v.vlen / 8 in
  let keys = List.init v.vr_count (fun i -> v.vr_base + i) in
  let storage =
    State.mirror_packed sc v.storage ~purpose:"vector register storage" ~first_key:v.vr_base
      ~entries:v.vr_count ~width:v.vlen ~eq:Bits.equal Fun.id
  in
  let w = v.writes in
  let entry, fields =
    List.fold_left
      (fun (lo, acc) (fd : Platform.field) ->
        (lo + fd.field_width, (fd.field, (lo, fd.field_width)) :: acc))
      (0, []) (List.rev w.layout)
  in
  let field e name =
    let lo, width = List.assoc name fields in
    Bits.field e ~lo ~width
  in
  let vec name width purpose =
    Bind.signal sc name { Bind.bits with dwidth = Exact width } ~purpose
  in
  let writes =
    let open Sig in
    let+ valid = vec w.w_valid w.w_ports "vector register write valid"
    and+ data = vec w.w_data (w.w_ports * entry) "vector register writes"
    and+ cycle = cycle c.clk in
    List.filter_map
      (fun port ->
        if not (Bits.bit valid port) then None
        else
          let e = Bits.field data ~lo:(port * entry) ~width:entry in
          Some
            {
              cycle;
              port;
              pc =
                (if List.mem_assoc "uop_pc" fields then Some (Bits.to_int_exn (field e "uop_pc"))
                 else None);
              reg = v.vr_base + Bits.to_int_exn (field e "rt_index");
              strobe = field e "rt_strobe";
              data = field e "rt_data";
            })
      (List.init w.w_ports Fun.id)
  in
  let always = Sig.const c.clk true in
  let nonempty e = Ev.filter (fun l -> l <> []) e in
  let fired = nonempty (Ev.when_ always writes) in
  Ev.subscribe fired (List.iter f);
  let merged =
    Ev.map
      (fun ws ->
        let regs = List.sort_uniq Int.compare (List.map (fun w -> w.reg) ws) in
        List.map
          (fun r ->
            let mine = List.filter (fun w -> w.reg = r) ws in
            let on i w = Bits.bit w.strobe i in
            ( r,
              ( of_bits n (fun i -> List.exists (on i) mine),
                of_bytes n (fun i ->
                    List.fold_left (fun b w -> if on i w then b lor byte w.data i else b) 0 mine) )
            ))
          regs)
      fired
  in
  let written =
    State.replay ~init:State.empty
      (fun old (strobe, data) ->
        let o = Option.value old ~default:{ known = Bits.zero n; value = Bits.zero v.vlen } in
        {
          known = of_bits n (fun i -> Bits.bit o.known i || Bits.bit strobe i);
          value = of_bytes n (fun i -> byte (if Bits.bit strobe i then data else o.value) i);
        })
      merged
  in
  let written' = State.previous c.clk written in
  let comparisons = ref 0 in
  let get (s : _ State.store) k = State.get (Sig.peek s.state) k in
  State.relate c.clk c.net ~source:model ~code ~keys
    [ State.keys storage; State.keys written' ]
    (fun k ->
      match (get written' k, get storage k) with
      | Some wr, Some s -> (
          incr comparisons;
          match
            List.find_opt
              (fun i -> Bits.bit wr.known i && byte wr.value i <> byte s i)
              (List.init n Fun.id)
          with
          | None -> None
          | Some i ->
              Some
                (Printf.sprintf "%s byte %d holds %02x, last written %02x" (Core.reg_name k) i
                   (byte s i) (byte wr.value i)))
      | _ -> None);
  let last =
    State.replay ~init:State.empty
      (fun old (cycle, pc) ->
        match old with Some (c, pcs) when c = cycle -> (c, pc :: pcs) | _ -> (cycle, [ pc ]))
      (Ev.map (List.map (fun w -> (w.reg, (w.cycle, w.pc)))) fired)
  in
  let last' = State.previous c.clk last in
  let retired = ref 0 in
  Ev.subscribe commits
    (List.iter (fun (cm : Commits.commit) ->
         match cm.dest with
         | Some (r, _) when (not cm.trap) && r >= v.vr_base && r < v.vr_base + v.vr_count -> (
             incr retired;
             let fail m =
               Diag.report c.net
                 (Diag.make ~severity:Error ~source:model ~code:retired_code
                    (Printf.sprintf "pc %08x retired %s, %s" cm.pc (Core.reg_name r) m))
             in
             match State.get (Sig.peek last'.state) r with
             | None -> fail "never written"
             | Some (cycle, pcs) ->
                 if not (List.mem (Some cm.pc) pcs || List.mem None pcs) then
                   fail
                     (Printf.sprintf "last written at cycle %d by %s" cycle
                        (String.concat ", "
                           (List.map
                              (function Some pc -> Printf.sprintf "pc %08x" pc | None -> "?")
                              pcs))))
         | _ -> ()));
  let history = ref [] in
  Ev.subscribe
    (Ev.tag (Sig.cycle c.clk) storage.changes)
    (fun (_, cycle) -> history := (cycle, Sig.peek storage.state) :: !history);
  fun (st : Sched.run_stats) ->
    let diags = List.of_seq (Diag.stream c.net) in
    let mine code = List.filter (fun (d : Diag.t) -> d.code = code) diags in
    {
      cycles = st.ticks.(0);
      relations =
        [
          (code, !comparisons, List.length (mine code));
          (retired_code, !retired, List.length (mine retired_code));
        ];
      failures =
        List.filteri
          (fun i _ -> i < 20)
          (List.filter (fun (d : Diag.t) -> List.mem d.code [ code; retired_code ]) diags);
      storage = State.bindings (Sig.peek storage.state);
      storage_at =
        Option.bind at (fun at ->
            List.find_opt (fun (cycle, _) -> cycle <= at) !history
            |> Option.map (fun (cycle, s) -> (cycle, State.bindings s)));
    }

let run ?at p tr f =
  let (Core.Any c) = Core.bind p tr ~model in
  let finish = graph ?at c f in
  finish (Core.run c)
