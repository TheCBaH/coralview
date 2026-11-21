[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type kind = Fma | Arith | Move | Memory | Other

type op = {
  cycle : int;
  pc : int option;
  unit : string;
  mnemonic : string option;
  sew : int;
  lmul : string;
  lmul_orig : string option;
  vl : int;
  vstart : int;
  tile : (int * int) option;
  kind : kind;
  float : bool;
  elements : int;
  ops : int;
}

type burst = { first : int; last : int; instructions : int; ops : int; flops : int }

let name = "ops"
let doc = "Vector operations at the RVV backend's dispatch: totals, bursts and ops per cycle."
let needs = [ "v_dispatch"; "dispatch_debug" ]

module SM = Map.Make (String)
module IM = Map.Make (Int)

module Config = struct
  type t = { gap : int; peak_window : int; features : string option }

  let default = { gap = 256; peak_window = 64; features = None }
end

let kind_jsont =
  Jsont.enum ~kind:"kind"
    [ ("fma", Fma); ("arith", Arith); ("move", Move); ("memory", Memory); ("other", Other) ]

module Event = struct
  type t = Op of op | Burst of burst

  let op =
    Codec.case "ops.op"
      (fun o -> Op o)
      (Jsont.Object.map
         (fun cycle pc unit mnemonic sew lmul lmul_orig vl vstart tile kind float elements ops ->
           {
             cycle;
             pc;
             unit;
             mnemonic;
             sew;
             lmul;
             lmul_orig;
             vl;
             vstart;
             tile;
             kind;
             float;
             elements;
             ops;
           })
      |> Jsont.Object.mem "cycle" Jsont.int ~enc:(fun (o : op) -> o.cycle)
      |> Codec.opt (fun (o : op) -> o.pc) "pc" Jsont.int
      |> Jsont.Object.mem "unit" Jsont.string ~enc:(fun (o : op) -> o.unit)
      |> Codec.opt (fun (o : op) -> o.mnemonic) "mnemonic" Jsont.string
      |> Jsont.Object.mem "sew" Jsont.int ~enc:(fun (o : op) -> o.sew)
      |> Jsont.Object.mem "lmul" Jsont.string ~enc:(fun (o : op) -> o.lmul)
      |> Codec.opt (fun (o : op) -> o.lmul_orig) "lmul_orig" Jsont.string
      |> Jsont.Object.mem "vl" Jsont.int ~enc:(fun (o : op) -> o.vl)
      |> Jsont.Object.mem "vstart" Jsont.int ~enc:(fun (o : op) -> o.vstart)
      |> Codec.opt
           (fun (o : op) -> o.tile)
           "tile"
           (Jsont.Object.map ~kind:"tile" (fun tm tk -> (tm, tk))
           |> Jsont.Object.mem "tm" Jsont.int ~enc:fst
           |> Jsont.Object.mem "tk" Jsont.int ~enc:snd
           |> Jsont.Object.finish)
      |> Jsont.Object.mem "kind" kind_jsont ~enc:(fun (o : op) -> o.kind)
      |> Jsont.Object.mem "float" Jsont.bool ~enc:(fun (o : op) -> o.float)
      |> Jsont.Object.mem "elements" Jsont.int ~enc:(fun (o : op) -> o.elements)
      |> Jsont.Object.mem "ops" Jsont.int ~enc:(fun (o : op) -> o.ops)
      |> Jsont.Object.finish)

  let burst =
    Codec.case "ops.burst"
      (fun b -> Burst b)
      (Jsont.Object.map (fun first last instructions ops flops ->
           { first; last; instructions; ops; flops })
      |> Jsont.Object.mem "first" Jsont.int ~enc:(fun b -> b.first)
      |> Jsont.Object.mem "last" Jsont.int ~enc:(fun b -> b.last)
      |> Jsont.Object.mem "instructions" Jsont.int ~enc:(fun b -> b.instructions)
      |> Jsont.Object.mem "ops" Jsont.int ~enc:(fun b -> b.ops)
      |> Jsont.Object.mem "flops" Jsont.int ~enc:(fun b -> b.flops)
      |> Jsont.Object.finish)

  let jsont =
    Codec.cases "ops.event"
      (function Op o -> Jsont.Object.Case.value op o | Burst b -> Jsont.Object.Case.value burst b)
      Jsont.Object.Case.[ make op; make burst ]

  let cycle = function Op o -> o.cycle | Burst b -> b.first
  let pc = function Op o -> o.pc | Burst _ -> None
end

type unit_total = { u_unit : string; u_instructions : int; u_elements : int; u_ops : int }
type peak = { p_window : int; p_ops : int; p_last : int }

module Summary = struct
  type t = {
    cycles : int;
    instructions : int;
    undecoded : int;
    ops : int;
    flops : int;
    bursts : int;
    busy : int;
    peak : peak option;
    units : unit_total list;
  }

  let unit_total =
    Jsont.Object.map ~kind:"unit" (fun u_unit u_instructions u_elements u_ops ->
        { u_unit; u_instructions; u_elements; u_ops })
    |> Jsont.Object.mem "unit" Jsont.string ~enc:(fun u -> u.u_unit)
    |> Jsont.Object.mem "instructions" Jsont.int ~enc:(fun u -> u.u_instructions)
    |> Jsont.Object.mem "elements" Jsont.int ~enc:(fun u -> u.u_elements)
    |> Jsont.Object.mem "ops" Jsont.int ~enc:(fun u -> u.u_ops)
    |> Jsont.Object.finish

  let peak =
    Jsont.Object.map ~kind:"peak" (fun p_window p_ops p_last -> { p_window; p_ops; p_last })
    |> Jsont.Object.mem "window" Jsont.int ~enc:(fun p -> p.p_window)
    |> Jsont.Object.mem "ops" Jsont.int ~enc:(fun p -> p.p_ops)
    |> Jsont.Object.mem "last" Jsont.int ~enc:(fun p -> p.p_last)
    |> Jsont.Object.finish

  let jsont =
    Codec.record "ops.summary"
      (fun cycles instructions undecoded ops flops bursts busy peak units ->
        { cycles; instructions; undecoded; ops; flops; bursts; busy; peak; units })
    |> Jsont.Object.mem "cycles" Jsont.int ~enc:(fun s -> s.cycles)
    |> Jsont.Object.mem "instructions" Jsont.int ~enc:(fun s -> s.instructions)
    |> Jsont.Object.mem "undecoded" Jsont.int ~enc:(fun s -> s.undecoded)
    |> Jsont.Object.mem "ops" Jsont.int ~enc:(fun s -> s.ops)
    |> Jsont.Object.mem "flops" Jsont.int ~enc:(fun s -> s.flops)
    |> Jsont.Object.mem "bursts" Jsont.int ~enc:(fun s -> s.bursts)
    |> Jsont.Object.mem "busy" Jsont.int ~enc:(fun s -> s.busy)
    |> Codec.opt (fun s -> s.peak) "peak" peak
    |> Jsont.Object.mem "units" (Jsont.list unit_total) ~enc:(fun s -> s.units)
    |> Jsont.Object.finish
end

(* By Rivet's mnemonic, without its suffix ([vfmacc] of [vfmacc.vf]). *)
let fused =
  [
    "vfmacc";
    "vfnmacc";
    "vfmsac";
    "vfnmsac";
    "vfmadd";
    "vfnmadd";
    "vfmsub";
    "vfnmsub";
    "vfwmacc";
    "vfwnmacc";
    "vfwmsac";
    "vfwnmsac";
    "vfwmaccbf16";
    "vmacc";
    "vnmsac";
    "vmadd";
    "vnmsub";
    "vwmacc";
    "vwmaccu";
    "vwmaccsu";
    "vwmaccus";
  ]

(* Zvt's tile matrix multiplies: tm x tn x tk multiply-accumulates, tn being vl. *)
let matmuls = [ "vtfmm"; "vtmmu"; "vtmms" ]

let moves =
  [ "vmv"; "vmv1r"; "vmv2r"; "vmv4r"; "vmv8r"; "vfmv"; "vmerge"; "vfmerge"; "vtmv"; "vtzero" ]

let config =
  [ "vsetvl"; "vsetvli"; "vsetivli"; "msetmtype"; "msetmtypei"; "msettn"; "msettm"; "msettk" ]

let base m = match String.index_opt m '.' with Some i -> String.sub m 0 i | None -> m

let classify unit = function
  | None -> Other
  | Some m ->
      let b = base m in
      if unit = "lsu" || unit = "vmelsu" then Memory
      else if List.mem b config then Other
      else if unit = "pmt" || List.mem b moves then Move
      else if List.mem b fused || List.mem b matmuls then Fma
      else Arith

let is_float = function
  | Some m ->
      String.starts_with ~prefix:"vf" m
      || String.starts_with ~prefix:"vmf" m
      || String.starts_with ~prefix:"vtf" m
  | None -> false

let lmul_name = function
  | 0 -> "1"
  | 1 -> "2"
  | 2 -> "4"
  | 3 -> "8"
  | 5 -> "1/8"
  | 6 -> "1/4"
  | 7 -> "1/2"
  | _ -> "reserved"

type st = {
  burst : burst option;
  bursts : int;
  busy : int;
  window : (int * int) list * (int * int) list;  (** (cycle, ops), oldest first, as a queue. *)
  in_window : int;
  peak : peak option;
  instructions : int;
  ops : int;
  flops : int;
  units : (int * int * int) SM.t;
  words : int IM.t;  (** Instruction words by PC, from the scalar core's dispatch. *)
  undecoded : int;
}

let empty =
  {
    burst = None;
    bursts = 0;
    busy = 0;
    window = ([], []);
    in_window = 0;
    peak = None;
    instructions = 0;
    ops = 0;
    flops = 0;
    units = SM.empty;
    words = IM.empty;
    undecoded = 0;
  }

let length b = b.last - b.first + 1

(* Drop the entries of the window at or before [before]. *)
let rec trim ~before ((front, back), sum) =
  match front with
  | (c, n) :: rest when c <= before -> trim ~before ((rest, back), sum - n)
  | _ :: _ -> ((front, back), sum)
  | [] -> if back = [] then (([], []), sum) else trim ~before ((List.rev back, []), sum)

let add (cfg : Config.t) (s, out) (o : op) =
  let n, e, k = Option.value (SM.find_opt o.unit s.units) ~default:(0, 0, 0) in
  let s =
    {
      s with
      instructions = s.instructions + 1;
      units = SM.add o.unit (n + 1, e + o.elements, k + o.ops) s.units;
    }
  in
  if o.ops = 0 then (s, Event.Op o :: out)
  else begin
    let flops = if o.float then o.ops else 0 in
    let fresh = { first = o.cycle; last = o.cycle; instructions = 1; ops = o.ops; flops } in
    let s, out =
      match s.burst with
      | Some b when o.cycle - b.last <= cfg.gap ->
          ( {
              s with
              burst =
                Some
                  {
                    b with
                    last = o.cycle;
                    instructions = b.instructions + 1;
                    ops = b.ops + o.ops;
                    flops = b.flops + flops;
                  };
            },
            out )
      | Some b ->
          ( { s with burst = Some fresh; bursts = s.bursts + 1; busy = s.busy + length b },
            Event.Burst b :: out )
      | None -> ({ s with burst = Some fresh }, out)
    in
    let (front, back), sum = (s.window, s.in_window) in
    let window, in_window =
      trim ~before:(o.cycle - cfg.peak_window) ((front, (o.cycle, o.ops) :: back), sum + o.ops)
    in
    let peak =
      match s.peak with
      | Some p when p.p_ops >= in_window -> s.peak
      | _ -> Some { p_window = cfg.peak_window; p_ops = in_window; p_last = o.cycle }
    in
    ( { s with window; in_window; peak; ops = s.ops + o.ops; flops = s.flops + flops },
      Event.Op o :: out )
  end

let build (cfg : Config.t) (c : _ Core.t) =
  let d = Core.block c "v_dispatch" c.platform.blocks.v_dispatch in
  let rivet =
    match Coral_isa.Rivet_decode.create ?features:cfg.features () with
    | Ok r -> r
    | Error e -> invalid_arg ("ops: " ^ e)
  in
  let sc = Core.scope c d.vd_scope in
  let entry, fields =
    List.fold_left
      (fun (lo, acc) (f : Platform.field) ->
        (lo + f.field_width, (f.field, (lo, f.field_width)) :: acc))
      (0, []) (List.rev d.vd_layout)
  in
  let field e name =
    let lo, width = List.assoc name fields in
    Bits.field_int e ~lo ~width
  in
  let vec name width purpose =
    Bind.signal sc name { Bind.bits with dwidth = Exact width } ~purpose
  in
  let uop e =
    let u = field e "uop_exe_unit" in
    let vl = field e "csr_vl" and vstart = field e "csr_vstart" in
    {
      cycle = 0;
      pc = Some (field e "uop_pc");
      unit = (match List.nth_opt d.units u with Some n -> n | None -> Printf.sprintf "unit%d" u);
      mnemonic = None;
      sew = 8 lsl field e "csr_sew";
      lmul = lmul_name (field e "csr_lmul");
      lmul_orig =
        (if List.mem_assoc "csr_lmul_orig" fields then Some (lmul_name (field e "csr_lmul_orig"))
         else None);
      vl;
      vstart;
      tile =
        (if List.mem_assoc "csr_tm" fields && List.mem_assoc "csr_tk" fields then
           Some (field e "csr_tm", field e "csr_tk")
         else None);
      kind = Other;
      float = false;
      elements = max 0 (vl - vstart);
      ops = 0;
    }
  in
  (* The scalar core dispatches a vector instruction before the backend takes its first uop. [uop]
     leaves the cycle to [resolve], which gets it from the tick. *)
  let resolve ~cycle words (o : op) =
    let mnemonic =
      match Option.bind o.pc (fun pc -> IM.find_opt pc words) with
      | None -> None
      | Some w -> (
          match Coral_isa.Rivet_decode.instruction rivet w with
          | Ok i -> Some i.mnemonic
          | Error _ -> None)
    in
    let kind = classify o.unit mnemonic in
    let elements =
      match (mnemonic, o.tile) with
      | Some m, Some (tm, tk) when List.mem (base m) matmuls -> tm * o.vl * tk
      | _ -> o.elements
    in
    {
      o with
      cycle;
      mnemonic;
      kind;
      float = is_float mnemonic;
      elements;
      ops = (match kind with Fma -> 2 * elements | Arith -> elements | _ -> 0);
    }
  in
  let uops =
    let open Sig in
    let+ valid = vec d.vd_valid d.vd_lanes "uop valid"
    and+ ready = vec d.vd_ready d.vd_lanes "uop taken"
    and+ uops = vec d.vd_uop (d.vd_lanes * entry) "dispatched uops" in
    List.filter_map
      (fun lane ->
        if Bits.bit valid lane && Bits.bit ready lane then
          let e = Bits.field uops ~lo:(lane * entry) ~width:entry in
          if field e "first_uop_valid" = 1 then Some (uop e) else None
        else None)
      (List.init d.vd_lanes Fun.id)
  in
  let input = Sig.map2 (fun ds us -> (ds, us)) (Core.present c (Core.dispatch c)) uops in
  let step ~cycle s ((ds : Core.dispatched list), us) =
    let words =
      List.fold_left (fun m (x : Core.dispatched) -> IM.add x.d_pc x.d_word m) s.words ds
    in
    let s = { s with words } in
    let s, out =
      List.fold_left
        (fun (s, out) o ->
          let o = resolve ~cycle s.words o in
          let s = if o.mnemonic = None then { s with undecoded = s.undecoded + 1 } else s in
          add cfg (s, out) o)
        (s, []) us
    in
    (s, List.rev out)
  in
  let out, st =
    Machine.run
      {
        name;
        init = empty;
        step =
          (fun ~tick s (ds, us) ->
            if ds = [] && us = [] then (s, []) else step ~cycle:tick.index s (ds, us));
        finish = (fun s -> Option.to_list (Option.map (fun b -> Event.Burst b) s.burst));
        every_tick = true;
      }
      input
  in
  ( out,
    fun (stats : Sched.run_stats) ->
      let s = Sig.peek st in
      let bursts, busy =
        match s.burst with Some b -> (s.bursts + 1, s.busy + length b) | None -> (s.bursts, s.busy)
      in
      {
        Summary.cycles = Core.cycles c stats;
        instructions = s.instructions;
        undecoded = s.undecoded;
        ops = s.ops;
        flops = s.flops;
        bursts;
        busy;
        peak = s.peak;
        units =
          List.map
            (fun (u_unit, (u_instructions, u_elements, u_ops)) ->
              { u_unit; u_instructions; u_elements; u_ops })
            (SM.bindings s.units);
      } )

let rate n d = if d = 0 then 0. else float_of_int n /. float_of_int d

let op_selected (ctx : Text.ctx) =
  let selected = Text.selected ctx.window in
  fun (o : op) -> selected ~cycle:o.cycle ~pc:(Option.value o.pc ~default:(-1))

(* The instruction names, and the operations by instruction, of the ops the window selects. *)
let profile_state (ctx : Text.ctx) =
  let names = ref IM.empty in
  let acc =
    Profile.Acc.create
      ~key:(fun (o : op) -> o.pc)
      ~weight:(fun (o : op) -> o.ops)
      ~total:(fun (o : op) -> o.elements)
      ()
  in
  let add (o : op) =
    (match o.pc with
    | Some pc -> names := IM.add pc (Option.value o.mnemonic ~default:("? " ^ o.unit)) !names
    | None -> ());
    Profile.Acc.add acc o
  in
  let print ppf =
    Format.fprintf ppf "operations by instruction:\n%8s %6s %10s %10s  %s\n" "pc" "count" "ops"
      "elements" "instruction";
    List.iteri
      (fun i (r : int Profile.row) ->
        if i < ctx.profile then
          Format.fprintf ppf "%08x %6d %10d %10d  %s\n" r.key r.count r.weight r.total
            (Option.value (IM.find_opt r.key !names) ~default:"?"))
      (Profile.Acc.rows acc)
  in
  (add, print)

let profile (ctx : Text.ctx) ppf _ : Event.t Text.sink =
  let add, print = profile_state ctx in
  let op_selected = op_selected ctx in
  {
    add = (function Event.Op o when op_selected o -> add o | _ -> ());
    finish = (fun () -> print ppf);
  }

let text (ctx : Text.ctx) ppf summary : Event.t Text.sink =
  let windowed = Text.windowed ctx.window in
  let op_selected = op_selected ctx in
  let padd, pprint = if ctx.profile > 0 then profile_state ctx else (ignore, fun _ -> ()) in
  let n = ref 0 and elements = ref 0 and ops = ref 0 and flops = ref 0 and units = ref SM.empty in
  let bursts = ref [] and shown = ref 0 and any = ref false in
  let add = function
    | Event.Op o when op_selected o ->
        incr n;
        elements := !elements + o.elements;
        ops := !ops + o.ops;
        if o.float then flops := !flops + o.ops;
        let c, e, p = Option.value (SM.find_opt o.unit !units) ~default:(0, 0, 0) in
        units := SM.add o.unit (c + 1, e + o.elements, p + o.ops) !units;
        padd o
    | Burst b when b.last >= ctx.window.first && b.first <= ctx.window.last ->
        any := true;
        if !shown < ctx.limit then begin
          incr shown;
          bursts := b :: !bursts
        end
    | _ -> ()
  in
  let finish () =
    let s : Summary.t = summary () in
    Format.fprintf ppf "root %s: %d cycles, %d vector instructions dispatched (%d not decoded)\n"
      ctx.root s.cycles s.instructions s.undecoded;
    Format.fprintf ppf "  %-6s %12s %12s %12s\n" "unit" "instructions" "elements" "ops";
    List.iter
      (fun u ->
        Format.fprintf ppf "  %-6s %12d %12d %12d\n" u.u_unit u.u_instructions u.u_elements u.u_ops)
      s.units;
    Format.fprintf ppf
      "%d ops (%d floating point) in %d bursts over %d cycles (%.1f%% of the trace)\n" s.ops s.flops
      s.bursts s.busy
      (100. *. rate s.busy s.cycles);
    Format.fprintf ppf "ops/cycle: %.3f over the trace, %.3f in bursts" (rate s.ops s.cycles)
      (rate s.ops s.busy);
    (match s.peak with
    | Some p ->
        Format.fprintf ppf ", peak %.3f over %d cycles to cycle %d\n" (rate p.p_ops p.p_window)
          p.p_window p.p_last
    | None -> Format.fprintf ppf "\n");
    if windowed then begin
      Format.fprintf ppf "%s: %d vector instructions, %d elements, %d ops (%d floating point)\n"
        (Text.describe ctx.window) !n !elements !ops !flops;
      List.iter
        (fun u ->
          match SM.find_opt u.u_unit !units with
          | None -> ()
          | Some (c, e, p) -> Format.fprintf ppf "  %-6s %12d %12d %12d\n" u.u_unit c e p)
        s.units
    end;
    if !any then begin
      Format.fprintf ppf "bursts:\n  %10s %10s %8s %8s %10s %9s\n" "first" "last" "cycles" "instrs"
        "ops" "ops/cycle";
      List.iter
        (fun b ->
          Format.fprintf ppf "  %10d %10d %8d %8d %10d %9.3f\n" b.first b.last (length b)
            b.instructions b.ops
            (rate b.ops (length b)))
        (List.rev !bursts)
    end;
    if ctx.profile > 0 then pprint ppf
  in
  { add; finish }

let perfetto (ctx : Text.ctx) events (s : Summary.t) =
  let window = match s.peak with Some p -> p.p_window | None -> Config.default.peak_window in
  let ops = Seq.filter_map (function Event.Op o -> Some o | Burst _ -> None) events in
  let bursts = Seq.filter_map (function Event.Burst b -> Some b | Op _ -> None) events in
  let per_window =
    Seq.fold_left
      (fun m (o : op) ->
        if o.ops = 0 then m
        else
          let w = o.cycle / window in
          IM.add w (o.ops + Option.value (IM.find_opt w m) ~default:0) m)
      IM.empty ops
  in
  let counters =
    let track = Printf.sprintf "ops per %d cycles" window in
    IM.fold
      (fun w n (acc, next) ->
        let acc =
          match next with
          | Some n when n <> w -> { Perfetto.c_track = track; cycle = n * window; value = 0 } :: acc
          | _ -> acc
        in
        ({ Perfetto.c_track = track; cycle = w * window; value = n } :: acc, Some (w + 1)))
      per_window ([], None)
    |> fun (acc, next) ->
    List.rev
      (match next with
      | Some w -> { Perfetto.c_track = track; cycle = w * window; value = 0 } :: acc
      | None -> acc)
  in
  {
    Perfetto.process = "ops " ^ ctx.root;
    slices =
      Seq.append
        (Seq.map
           (fun (b : burst) ->
             {
               Perfetto.track = "bursts";
               name = Printf.sprintf "%d ops" b.ops;
               start = b.first;
               stop = b.last;
               args =
                 [
                   ("instructions", string_of_int b.instructions);
                   ("flops", string_of_int b.flops);
                   ("ops/cycle", Printf.sprintf "%.3f" (rate b.ops (length b)));
                 ];
             })
           bursts)
        (Seq.map
           (fun (o : op) ->
             {
               Perfetto.track = o.unit;
               name = Option.value o.mnemonic ~default:"?";
               start = o.cycle;
               stop = o.cycle;
               args =
                 ([ ("vl", string_of_int o.vl); ("ops", string_of_int o.ops) ]
                 @ match o.pc with Some pc -> [ ("pc", Printf.sprintf "%08x" pc) ] | None -> []);
             })
           ops);
    counters = List.to_seq counters;
  }
