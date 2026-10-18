[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type summary = {
  cycles : int;
  relations : (string * int * int) list;
  flushes : int;
  failures : Diag.t list;
  storage : (int * int) list;
  architectural : (int * int) list;
  storage_at : (int * (int * int) list) option;
}

let model = "registers"
let name = model
let doc = "The x/f register files, related to writes, scoreboards and retirements."

let needs =
  [
    "x_registers";
    "f_registers";
    "regfile_writeback";
    "float_writeback";
    "dispatch_debug";
    "retirement_debug";
  ]

let codes =
  [ "registers.storage"; "registers.scoreboard"; "registers.flushed"; "registers.architectural" ]

type sb = { pending : bool; flushed : bool }

let clear = { pending = false; flushed = false }

let sb_next old (set, clr, flush) =
  let s = Option.value old ~default:clear in
  if flush then { flushed = (s.pending || s.flushed) && not clr; pending = set }
  else { pending = (s.pending && not clr) || set; flushed = s.flushed && not clr }

let file ~count (c : _ Core.t) writes commits (rf : Platform.register_file) =
  let clk = c.clk and net = c.net in
  let keys = List.init rf.count (fun i -> rf.base + rf.first + i) in
  let mine k = List.mem k keys in
  let sc = Core.scope c rf.rf_scope in
  let storage =
    State.mirror_fields sc ~purpose:"register storage"
      (List.map
         (fun k ->
           ( k,
             List.map
               (fun (f : Platform.field) ->
                 (Platform.name_of f.field (k - rf.base), Bind.Exact f.field_width))
               rf.fields ))
         keys)
      (fun ls -> Bits.to_int_exn (Bits.concat (List.map (fun (l : Logic.t) -> l.bits) ls)))
  in
  let bitmap name purpose =
    State.mirror_packed sc name ~purpose ~first_key:rf.base ~entries:32 ~width:1 (fun b ->
        Bits.bit b 0)
  in
  let sb = bitmap rf.scoreboard "write pending"
  and fsb = bitmap rf.flushed_scoreboard "flushed write" in
  let flush = Bind.signal sc rf.flush Bind.bool ~purpose:"pipeline flush" in
  let msc = Core.scope c rf.marks.m_scope in
  let marks =
    Core.present c
      (List.init rf.marks.m_ports (fun i ->
           let open Sig in
           let+ v =
             Bind.signal msc
               (Platform.name_of rf.marks.m_valid i)
               Bind.bool ~purpose:"write announced"
           and+ a =
             Bind.signal msc
               (Platform.name_of rf.marks.m_addr i)
               Bind.uint ~purpose:"register announced"
           in
           if v && mine (rf.base + a) then Some (rf.base + a) else None))
  in
  let written_now =
    Sig.map
      (List.filter_map (fun (w : Core.write) -> if mine w.reg then Some (w.reg, w.value) else None))
      writes
  in
  let nonempty e = Ev.filter (fun l -> l <> []) e in
  let always = Sig.const clk true in
  let written =
    State.replay ~init:State.empty (fun _ v -> v) (nonempty (Ev.when_ always written_now))
  in
  let sb_inputs =
    let open Sig in
    let+ marks = marks and+ w = written_now and+ flush = flush in
    let clr = List.map fst w in
    let touched = if flush then keys else List.sort_uniq Int.compare (marks @ clr) in
    List.map (fun k -> (k, (List.mem k marks, List.mem k clr, flush))) touched
  in
  let replayed = State.replay ~init:State.empty sb_next (nonempty (Ev.when_ always sb_inputs)) in
  let retired =
    Ev.map
      (List.filter_map (fun (cm : Commits.commit) ->
           match cm.dest with
           | Some (r, Some v) when (not cm.trap) && mine r -> Some (r, v)
           | _ -> None))
      commits
  in
  let architectural = State.replay ~init:State.empty (fun _ v -> v) (nonempty retired) in
  let unretired =
    State.replay ~init:State.empty
      (fun old d -> Option.value old ~default:0 + d)
      (nonempty
         (Ev.merge ( @ )
            (Ev.when_ always (Sig.map (List.map (fun (k, _) -> (k, 1))) written_now))
            (Ev.map (List.map (fun (k, _) -> (k, -1))) retired)))
  in
  let get (s : _ State.store) k = State.get (Sig.peek s.state) k in
  let relate code dirty check =
    State.relate clk net ~source:model ~code ~keys dirty (fun k ->
        match check k with
        | `Skip -> None
        | `Pass ->
            count code;
            None
        | `Fail m ->
            count code;
            Some m)
  in
  Ev.subscribe (Ev.filter Fun.id (Ev.when_ always flush)) (fun _ -> count "flushes");
  let written' = State.previous clk written and replayed' = State.previous clk replayed in
  let name k = Core.reg_name k in
  relate "registers.storage"
    [ State.keys storage; State.keys written' ]
    (fun k ->
      match (get written' k, get storage k) with
      | Some w, Some s ->
          if w = s then `Pass
          else `Fail (Printf.sprintf "%s holds %08x, last written %08x" (name k) s w)
      | _ -> `Skip);
  let bit code (store : _ State.store) proj =
    relate code
      [ State.keys store; State.keys replayed' ]
      (fun k ->
        let want = proj (Option.value (get replayed' k) ~default:clear) in
        match get store k with
        | Some have when have <> want ->
            `Fail
              (Printf.sprintf "%s bit is %b, the marks, writebacks and flushes give %b" (name k)
                 have want)
        | Some _ -> `Pass
        | None -> `Skip)
  in
  bit "registers.scoreboard" sb (fun s -> s.pending);
  bit "registers.flushed" fsb (fun s -> s.flushed);
  relate "registers.architectural"
    [ State.keys storage; State.keys sb; State.keys unretired; State.keys architectural ]
    (fun k ->
      if get sb k = Some true || Option.value (get unretired k) ~default:0 > 0 then `Skip
      else
        match (get architectural k, get storage k) with
        | Some a, Some s when a <> s ->
            `Fail (Printf.sprintf "%s retired as %08x, storage holds %08x" (name k) a s)
        | Some _, Some _ -> `Pass
        | _ -> `Skip);
  (storage, architectural)

let graph ?at (c : _ Core.t) =
  let counts = Hashtbl.create 8 in
  let count k =
    Hashtbl.replace counts k (1 + Option.value (Hashtbl.find_opt counts k) ~default:0)
  in
  let p = c.platform in
  let writes = Core.present c (Core.writes c) in
  let commits, _ = Commits.events c in
  let files =
    List.map (file ~count c writes commits)
      [
        Core.block c "x_registers" p.blocks.x_registers;
        Core.block c "f_registers" p.blocks.f_registers;
      ]
  in
  (* Snapshots are persistent, so keeping one per change keeps every past state. *)
  let history = ref [] in
  List.iter
    (fun ((storage : _ State.store), _) ->
      Ev.subscribe
        (Ev.tag (Sig.cycle c.clk) storage.changes)
        (fun (_, cycle) ->
          history :=
            (cycle, List.map (fun ((s : _ State.store), _) -> Sig.peek s.state) files) :: !history))
    files;
  fun (st : Sched.run_stats) ->
    let union snaps = List.concat_map State.bindings snaps in
    {
      cycles = st.ticks.(0);
      relations =
        List.map
          (fun code ->
            ( code,
              Option.value (Hashtbl.find_opt counts code) ~default:0,
              Seq.fold_left
                (fun n (d : Diag.t) -> if d.code = code then n + 1 else n)
                0 (Diag.stream c.net) ))
          codes;
      flushes = Option.value (Hashtbl.find_opt counts "flushes") ~default:0;
      failures =
        List.of_seq
          (Seq.take 20 (Seq.filter (fun (d : Diag.t) -> List.mem d.code codes) (Diag.stream c.net)));
      storage = union (List.map (fun ((s : _ State.store), _) -> Sig.peek s.state) files);
      architectural = union (List.map (fun (_, (a : _ State.store)) -> Sig.peek a.state) files);
      storage_at =
        Option.bind at (fun at ->
            List.find_opt (fun (cycle, _) -> cycle <= at) !history
            |> Option.map (fun (cycle, snaps) -> (cycle, union snaps)));
    }

module Config = struct
  type t = { at : int option  (** Also keep the storage as of this cycle. *) }

  let default = { at = None }
end

module Event = struct
  type t = |

  let jsont =
    Jsont.map ~kind:"registers.event"
      ~dec:(fun () -> invalid_arg "registers has no events")
      ~enc:(function (_ : t) -> .)
      (Jsont.null ())

  let cycle : t -> int = function _ -> .
  let pc : t -> int option = function _ -> .
end

module Summary = struct
  type t = summary

  let relation =
    Jsont.Object.map ~kind:"relation" (fun code comparisons failures ->
        (code, comparisons, failures))
    |> Jsont.Object.mem "code" Jsont.string ~enc:(fun (c, _, _) -> c)
    |> Jsont.Object.mem "comparisons" Jsont.int ~enc:(fun (_, n, _) -> n)
    |> Jsont.Object.mem "failures" Jsont.int ~enc:(fun (_, _, f) -> f)
    |> Jsont.Object.finish

  let reg =
    Jsont.Object.map ~kind:"register" (fun reg value -> (reg, value))
    |> Jsont.Object.mem "reg" Jsont.int ~enc:fst
    |> Jsont.Object.mem "value" Jsont.int ~enc:snd
    |> Jsont.Object.finish

  let at =
    Jsont.Object.map ~kind:"storage_at" (fun cycle storage -> (cycle, storage))
    |> Jsont.Object.mem "cycle" Jsont.int ~enc:fst
    |> Jsont.Object.mem "storage" (Jsont.list reg) ~enc:snd
    |> Jsont.Object.finish

  let jsont =
    Codec.record "registers.summary"
      (fun cycles relations flushes failures storage architectural storage_at ->
        { cycles; relations; flushes; failures; storage; architectural; storage_at })
    |> Jsont.Object.mem "cycles" Jsont.int ~enc:(fun s -> s.cycles)
    |> Jsont.Object.mem "relations" (Jsont.list relation) ~enc:(fun s -> s.relations)
    |> Jsont.Object.mem "flushes" Jsont.int ~enc:(fun s -> s.flushes)
    |> Jsont.Object.mem "failures" (Jsont.list Codec.diag) ~enc:(fun s -> s.failures)
    |> Jsont.Object.mem "storage" (Jsont.list reg) ~enc:(fun s -> s.storage)
    |> Jsont.Object.mem "architectural" (Jsont.list reg) ~enc:(fun s -> s.architectural)
    |> Codec.opt (fun s -> s.storage_at) "storage_at" at
    |> Jsont.Object.finish
end

let build (cfg : Config.t) (c : _ Core.t) = (Ev.never c.clk, graph ?at:cfg.at c)
let status (s : summary) = if s.failures <> [] then 1 else 0

let text (ctx : Text.ctx) (_ : Event.t list) (s : summary) =
  Printf.printf "root %s: %d cycles\n" ctx.root s.cycles;
  List.iter
    (fun (code, checks, n) -> Printf.printf "%-26s %8d comparisons, %d failures\n" code checks n)
    s.relations;
  Printf.printf "%d pipeline flushes\n" s.flushes;
  let table title regs =
    Printf.printf "%s:\n" title;
    List.iteri
      (fun i (r, v) ->
        Printf.printf "  %-4s %08x%s" (Core.reg_name r) v (if i mod 6 = 5 then "\n" else ""))
      regs;
    print_newline ()
  in
  Option.iter
    (fun (cycle, regs) -> table (Printf.sprintf "storage at cycle %d" cycle) regs)
    s.storage_at;
  table "storage at the end" s.storage;
  let differ = List.filter (fun (r, v) -> List.assoc_opt r s.storage <> Some v) s.architectural in
  if differ <> [] then table "architectural values that differ from storage at the end" differ;
  List.iteri (fun i d -> if i < ctx.limit then Format.printf "%a@." Diag.pp d) s.failures
