[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Coralview

let probe path =
  let { Vcd.header; simulation } = Vcd_fst.open_file path in
  let signals = Vcd.Resolver.fold (fun _ n -> n + 1) (Vcd.Resolver.make header) 0 in
  let times, changes, last =
    Seq.fold_left
      (fun (t, c, last) -> function
        | Vcd_ast.Timestamp ts -> (t + 1, c, Some ts)
        | Vcd_ast.Change _ -> (t, c + 1, last)
        | _ -> (t, c, last))
      (0, 0, None) simulation
  in
  Format.printf "signals %d@.timestamps %d@.changes %d@.last %a@." signals times changes
    (Format.pp_print_option Vcd_types.Timestamp.pp)
    last

let fail ?(code = 1) msg =
  flush stdout;
  prerr_endline msg;
  exit code

(* A probe that does not resolve means the platform description is wrong for this trace. *)
let guard (p : Platform.t) f =
  match f () with
  | x -> x
  | exception Hwfrp.Bind.Unbound (r, s) ->
      fail ~code:3
        (Format.asprintf "platform %s does not match the trace (model %s):@\n%a" p.name r.model
           Hwfrp.Bind.pp_entry (r, s))
  | exception Core.No_block (platform, block) ->
      fail ~code:2 (Printf.sprintf "platform %s describes no %s block" platform block)

let decoder features =
  match Rivet_decode.create ?features () with
  | Ok d -> d
  | Error e ->
      prerr_endline ("invalid --features: " ^ e);
      exit 2

let decode features words =
  let d = decoder features in
  List.iter
    (fun w ->
      match Rivet_decode.decode d (int_of_string ("0x" ^ w)) with
      | Ok s -> Printf.printf "%s  %s\n" w s
      | Error e -> Printf.printf "%s  error: %s\n" w e)
    words

let tree ~depth ~vars path scope =
  let { Vcd.header; _ } = Vcd_fst.open_file path in
  let rec total (s : Vcd_ast.scope_node) =
    List.length s.vars + List.fold_left (fun n c -> n + total c) 0 s.children
  in
  let rec show indent d (s : Vcd_ast.scope_node) =
    Printf.printf "%s%s %d/%d\n" indent s.s_name (List.length s.vars) (total s);
    if d < depth then List.iter (show (indent ^ "  ") (d + 1)) s.children
  in
  let rec find nodes = function
    | [] -> nodes
    | n :: rest ->
        List.concat_map
          (fun (s : Vcd_ast.scope_node) -> if s.s_name = n then find s.children rest else [])
          nodes
  in
  let parts = if scope = "" then [] else String.split_on_char '/' scope in
  let parent = match List.rev parts with [] -> [] | _ :: up -> find header.scopes (List.rev up) in
  let here =
    match List.rev parts with
    | [] -> header.scopes
    | last :: _ -> List.filter (fun (s : Vcd_ast.scope_node) -> s.s_name = last) parent
  in
  if here = [] then fail ("no scope " ^ scope);
  List.iter
    (fun (s : Vcd_ast.scope_node) ->
      if vars then
        List.iter (fun (v : Vcd_ast.var_decl) -> Printf.printf "%s %d\n" v.ref v.size) s.vars
      else show "" 0 s)
    here

type window = { w_first : int; w_last : int; w_pcs : int list }

let selected w ~cycle ~pc =
  cycle >= w.w_first && cycle <= w.w_last && (w.w_pcs = [] || List.mem pc w.w_pcs)

let commits p features ~window limit profile path =
  let d = decoder features in
  let shown = ref 0 in
  let by_pc = Hashtbl.create 256 in
  let disasm w = match w with Some w -> Rivet_decode.disasm d w | None -> "?" in
  let delta a b = match (a, b) with Some a, Some b -> string_of_int (b - a) | _ -> "-" in
  let print (c : Commits.commit) =
    let n, charged, lat, word =
      Option.value (Hashtbl.find_opt by_pc c.pc) ~default:(0, 0, 0, c.word)
    in
    let l = match c.dispatched with Some x -> c.retired - x | None -> 0 in
    Hashtbl.replace by_pc c.pc (n + 1, charged + c.charged, lat + l, word);
    if selected window ~cycle:c.retired ~pc:c.pc && !shown < limit then begin
      incr shown;
      Printf.printf "%8d %d %08x %s %-32s %-16s %3s %3s %3d%s\n" c.retired c.lane c.pc
        (match c.word with Some w -> Printf.sprintf "%08x" w | None -> "????????")
        (disasm c.word)
        (match c.dest with
        | Some (r, Some v) -> Printf.sprintf "%s=%08x" (Core.reg_name r) v
        | Some (r, None) -> Core.reg_name r ^ "=?"
        | None -> if c.store then "store" else "")
        (delta c.dispatched (Some c.retired))
        (delta c.dispatched c.written) c.charged
        (if c.trap then "  TRAP" else "")
    end
  in
  let s = Commits.run p (Hwfrp.Trace.open_file path) print in
  let root = Platform.root p in
  Printf.printf
    "root %s: %d cycles, %d before the first dispatch, %d later with nothing in flight; %d retires \
     without dispatch, %d dispatches skipped, %d values missing, %d in flight at the end\n"
    (Vcd_types.Reference.to_string root)
    s.cycles s.before s.empty s.unmatched_retires s.skipped s.missing_values s.in_flight;
  if s.pending <> [] then begin
    Printf.printf "in flight at the end, oldest first:\n";
    List.iter
      (fun (pc, word, cycle) ->
        Printf.printf "  dispatched %8d pc %08x %08x %s\n" cycle pc word (disasm (Some word)))
      s.pending
  end;
  if profile > 0 then begin
    let rows = Hashtbl.fold (fun pc v acc -> (pc, v) :: acc) by_pc [] in
    let rows = List.sort (fun (_, (_, a, _, _)) (_, (_, b, _, _)) -> Int.compare b a) rows in
    Printf.printf "%8s %6s %7s %6s %8s  %s\n" "pc" "count" "cycles" "share" "d->r" "instruction";
    List.iteri
      (fun i (pc, (n, charged, lat, word)) ->
        if i < profile then
          Printf.printf "%08x %6d %7d %5.1f%% %8.2f  %s\n" pc n charged
            (100. *. float charged /. float (max 1 s.cycles))
            (float lat /. float n)
            (disasm word))
      rows
  end

let stalls p profile path =
  let counts = Hashtbl.create 64 and by_pc = Hashtbl.create 64 in
  let bump h k = Hashtbl.replace h k (1 + Option.value (Hashtbl.find_opt h k) ~default:0) in
  let cycles =
    Stalls.run p (Hwfrp.Trace.open_file path) (fun _ lanes ->
        List.iter
          (fun (l : Stalls.lane) ->
            bump counts (l.lane, l.reason);
            if l.lane = 0 && l.reason <> Dispatched && l.reason <> Empty then
              bump by_pc (l.pc, l.word, l.reason))
          lanes)
  in
  let root = Platform.root p in
  let lanes = Hashtbl.fold (fun (l, _) _ n -> max n (l + 1)) counts 0 in
  Printf.printf "root %s: %d cycles\n%-14s" (Vcd_types.Reference.to_string root) cycles "reason";
  for l = 0 to lanes - 1 do
    Printf.printf " %7s" (Printf.sprintf "lane%d" l)
  done;
  print_newline ();
  List.iter
    (fun r ->
      if List.exists (fun l -> Hashtbl.mem counts (l, r)) (List.init lanes Fun.id) then begin
        Printf.printf "%-14s" (Stalls.reason_name r);
        for l = 0 to lanes - 1 do
          Printf.printf " %7d" (Option.value (Hashtbl.find_opt counts (l, r)) ~default:0)
        done;
        print_newline ()
      end)
    Stalls.
      [
        Dispatched;
        Empty;
        Behind;
        Halted;
        Interlock;
        Raw;
        Waw;
        Float_hazard;
        Lsu_queue;
        Rvv_queue;
        Rob_full;
        Trap_pending;
        Csr_serialize;
        Unit_busy;
        Other;
      ];
  if profile > 0 then begin
    let d = decoder None in
    Printf.printf "lane 0 blocked, by instruction:\n%8s %6s %-14s %s\n" "pc" "cycles" "reason"
      "instruction";
    Hashtbl.fold (fun k n acc -> (k, n) :: acc) by_pc []
    |> List.sort (fun (_, a) (_, b) -> Int.compare b a)
    |> List.iteri (fun i ((pc, word, r), n) ->
        if i < profile then
          Printf.printf "%08x %6d %-14s %s\n" pc n (Stalls.reason_name r)
            (Rivet_decode.disasm d word))
  end

let memory p ~region ~window limit path =
  let shown = ref 0 and reads = ref 0 and writes = ref 0 and faults = ref 0 in
  let by_pc = Hashtbl.create 64 in
  let on_fault (f : Memory.fault) =
    incr faults;
    if selected window ~cycle:f.f_cycle ~pc:f.f_pc then
      Printf.printf "%8d fault %s pc %08x addr %08x%s, %s\n" f.f_cycle
        (if f.f_write then "W" else "R")
        f.f_pc f.f_addr (region f.f_addr)
        (match f.request with
        | Some (cycle, addr) -> Printf.sprintf "requested at %d, addr %08x" cycle addr
        | None -> "no request seen")
  in
  let () =
    Memory.run ~on_fault p (Hwfrp.Trace.open_file path) (fun (a : Memory.access) ->
        incr (if a.write then writes else reads);
        Hashtbl.replace by_pc a.pc (1 + Option.value (Hashtbl.find_opt by_pc a.pc) ~default:0);
        if selected window ~cycle:a.cycle ~pc:a.pc && !shown < limit then begin
          incr shown;
          Printf.printf "%8d %s %s pc %08x addr %08x%s %d bytes %0*x\n" a.cycle
            (match a.bus with `Tcm -> "tcm" | `External -> "ext")
            (if a.write then "W" else "R")
            a.pc a.addr (region a.addr) (List.length a.bytes)
            (2 * List.length a.bytes)
            (Memory.value a)
        end)
  in
  let root = Platform.root p in
  Printf.printf "root %s: %d read and %d write requests from %d PCs, %d faults\n"
    (Vcd_types.Reference.to_string root)
    !reads !writes (Hashtbl.length by_pc) !faults

let tiles p limit path =
  let shown = ref 0 and n = ref 0 and by_pc = Hashtbl.create 64 in
  let file =
    Tiles.run p (Hwfrp.Trace.open_file path) (fun (w : Tiles.write) ->
        incr n;
        let k = w.pc in
        let c, first, _ = Option.value (Hashtbl.find_opt by_pc k) ~default:(0, w.cycle, w.cycle) in
        Hashtbl.replace by_pc k (c + 1, first, w.cycle);
        if !shown < limit then begin
          incr shown;
          Printf.printf "%8d blk%d port%d %s tile %2d sub %2d mask %04x %s\n" w.cycle w.block w.port
            (match w.pc with Some pc -> Printf.sprintf "pc %08x" pc | None -> "load       ")
            w.tile w.sub w.mask (Hwfrp.Bits.to_hex w.data)
        end)
  in
  let root = Platform.root p in
  Printf.printf "root %s: %d sub-tile writes; %d of 256 sub-tiles written\n"
    (Vcd_types.Reference.to_string root)
    !n (Hashtbl.length file);
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) by_pc []
  |> List.sort compare
  |> List.iter (fun (pc, (c, first, last)) ->
      Printf.printf "  %s: %d writes, cycles %d-%d\n"
        (match pc with Some pc -> Printf.sprintf "pc %08x" pc | None -> "tile loads ")
        c first last)

let registers p ~at limit path =
  let tr = Hwfrp.Trace.open_file path in
  let s = Registers.run ?at p tr in
  Printf.printf "root %s: %d cycles\n" (Vcd_types.Reference.to_string (Platform.root p)) s.cycles;
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
  if s.failures <> [] then begin
    List.iteri (fun i d -> if i < limit then Format.printf "%a@." Hwfrp.Diag.pp d) s.failures;
    exit 1
  end

let vectors p ~at limit path =
  let shown = ref 0 and n = ref 0 and by_pc = Hashtbl.create 64 in
  let s =
    Vectors.run ?at p (Hwfrp.Trace.open_file path) (fun (w : Vectors.write) ->
        incr n;
        let c, regs, first, _ =
          Option.value (Hashtbl.find_opt by_pc w.pc) ~default:(0, [], w.cycle, w.cycle)
        in
        Hashtbl.replace by_pc w.pc
          (c + 1, List.sort_uniq Int.compare (w.reg :: regs), first, w.cycle);
        if !shown < limit then begin
          incr shown;
          Printf.printf "%8d port%d %s %-3s strobe %s %s\n" w.cycle w.port
            (match w.pc with Some pc -> Printf.sprintf "pc %08x" pc | None -> "-")
            (Core.reg_name w.reg) (Hwfrp.Bits.to_hex w.strobe) (Hwfrp.Bits.to_hex w.data)
        end)
  in
  Printf.printf "root %s: %d cycles, %d vector register writes from %d PCs\n"
    (Vcd_types.Reference.to_string (Platform.root p))
    s.cycles !n (Hashtbl.length by_pc);
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) by_pc []
  |> List.sort compare
  |> List.iter (fun (pc, (c, regs, first, last)) ->
      Printf.printf "  %s: %d writes to %s, cycles %d-%d\n"
        (match pc with Some pc -> Printf.sprintf "pc %08x" pc | None -> "-")
        c
        (String.concat " " (List.map Core.reg_name regs))
        first last);
  List.iter
    (fun (code, checks, n) -> Printf.printf "%-26s %8d comparisons, %d failures\n" code checks n)
    s.relations;
  let table title regs =
    Printf.printf "%s:\n" title;
    List.iter
      (fun (r, v) -> Printf.printf "  %-4s %s\n" (Core.reg_name r) (Hwfrp.Bits.to_hex v))
      regs
  in
  Option.iter
    (fun (cycle, regs) -> table (Printf.sprintf "storage at cycle %d" cycle) regs)
    s.storage_at;
  table "storage at the end" s.storage;
  if s.failures <> [] then begin
    List.iter (Format.printf "%a@." Hwfrp.Diag.pp) s.failures;
    exit 1
  end

let json_string s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (fun ch ->
      match ch with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let signals platform ~raw ~json ~changes ~cycles:(from_cycle, to_cycle) ~times:(from_time, to_time)
    path paths =
  let tr = Hwfrp.Trace.open_file path in
  (try Signals.require tr paths
   with Signals.Missing p -> fail ~code:3 ("no signal " ^ p ^ " in the trace"));
  let phase, run =
    if raw then begin
      if from_cycle <> None || to_cycle <> None then
        fail ~code:2 "--raw selects timestamps: use --from-time and --to-time";
      ( "raw",
        Signals.raw tr paths
          ~from:(Option.value from_time ~default:0L)
          ~until:(Option.value to_time ~default:Int64.max_int) )
    end
    else begin
      if from_time <> None || to_time <> None then
        fail ~code:2 "--from-time and --to-time select raw timestamps: add --raw";
      let (p : Platform.t) = platform () in
      if not json then
        Printf.printf "# sampled %s on %s at %s\n"
          (Signals.sample_rule_name p.sample)
          p.clock
          (Vcd_types.Reference.to_string (Platform.root p));
      ( Signals.sample_rule_name p.sample,
        fun ~changes f ->
          guard p (fun () ->
              Signals.sampled p tr paths
                ~from:(Option.value from_cycle ~default:0)
                ~until:(Option.value to_cycle ~default:max_int)
                ~changes f) )
    end
  in
  let print (r : Signals.record) =
    let value = Signals.to_string r.value in
    if json then
      Printf.printf "{\"phase\":\"%s\",%s\"time\":%Ld,\"path\":%s,\"width\":%d,\"value\":\"%s\"}\n"
        phase
        (match r.cycle with Some c -> Printf.sprintf "\"cycle\":%d," c | None -> "")
        r.time (json_string r.path) r.width value
    else
      Printf.printf "%8s %10Ld %4d %s %s\n"
        (match r.cycle with Some c -> string_of_int c | None -> "-")
        r.time r.width r.path value
  in
  run ~changes print

let traps p path =
  let s = Traps.run p (Hwfrp.Trace.open_file path) in
  let at = function Some c -> Printf.sprintf "at %d" c | None -> "never" in
  let fault (f : Traps.fault) =
    Printf.printf "%8d %s fault: cause %d (%s), pc %08x, mtval %08x\n" f.cycle f.source f.cause
      (Traps.cause_name f.cause) f.pc f.value;
    Printf.printf "         csr      mcause/mepc/mtval hold them %s\n" (at f.csr);
    let ret = function
      | Some (r : Traps.retirement) ->
          Printf.sprintf "at %d%s" r.at (if r.trapped then " as a trap" else "")
      | None -> "never"
    in
    Printf.printf "         pc       retired up to the fault %s, after it %s\n"
      (ret f.retired_before) (ret f.retired_after);
    Printf.printf "         handler  %08x dispatched %s, retired %s: %s\n" f.handler
      (at f.dispatched) (at f.delivered)
      (match f.delivered with
      | Some _ -> "delivered"
      | None -> Printf.sprintf "not delivered by cycle %d" f.until)
  and change (c : Traps.csr_change) =
    Printf.printf "%8d csr change with no fault: mcause %d (%s), mepc %08x, mtval %08x\n" c.c_cycle
      c.c_mcause (Traps.cause_name c.c_mcause) c.c_mepc c.c_mtval
  in
  List.map (fun (f : Traps.fault) -> (f.cycle, fun () -> fault f)) s.faults
  @ List.map (fun (c : Traps.csr_change) -> (c.c_cycle, fun () -> change c)) s.unmatched
  |> List.stable_sort (fun (a, _) (b, _) -> compare a b)
  |> List.iter (fun (_, print) -> print ());
  let delivered =
    List.length (List.filter (fun (f : Traps.fault) -> f.delivered <> None) s.faults)
  in
  Printf.printf "root %s: %d cycles, %d faults, %d delivered\n"
    (Vcd_types.Reference.to_string (Platform.root p))
    s.cycles (List.length s.faults) delivered

type model = { name : string; about : string; needs : string list; build : 'c. 'c Core.t -> unit }

let models =
  [
    {
      name = Commits.model;
      about = "retired instructions with values and per-instruction cycles";
      needs = Commits.needs;
      build = (fun c -> ignore (Commits.graph c ignore : Hwfrp.Sched.run_stats -> _));
    };
    {
      name = Stalls.model;
      about = "why each dispatch lane did not dispatch, per cycle";
      needs = Stalls.needs;
      build = (fun c -> ignore (Stalls.graph c (fun _ _ -> ()) : Hwfrp.Sched.run_stats -> _));
    };
    {
      name = Memory.model;
      about = "LSU data accesses with PC, address and data";
      needs = Memory.needs;
      build = (fun c -> ignore (Memory.graph c ignore : Hwfrp.Sched.run_stats -> _));
    };
    {
      name = Registers.model;
      about = "x/f register files: storage, scoreboard and retired state related";
      needs = Registers.needs;
      build = (fun c -> ignore (Registers.graph c : Hwfrp.Sched.run_stats -> _));
    };
    {
      name = Tiles.model;
      about = "VME tile register writes, by PC";
      needs = Tiles.needs;
      build = (fun c -> ignore (Tiles.graph c ignore : Hwfrp.Sched.run_stats -> _));
    };
    {
      name = Traps.model;
      about = "faults, the CSR updates they cause and whether the handler ran";
      needs = Traps.needs;
      build = (fun c -> ignore (Traps.graph c : Hwfrp.Sched.run_stats -> _));
    };
    {
      name = Vectors.model;
      about = "vector register file: storage related to its write ports";
      needs = Vectors.needs;
      build = (fun c -> ignore (Vectors.graph c ignore : Hwfrp.Sched.run_stats -> _));
    };
  ]

let available p =
  List.filter (fun m -> List.for_all (fun b -> List.mem b (Platform.blocks p)) m.needs) models

let platforms manifest =
  let manifest =
    Option.map (fun f -> match Manifest.load f with Ok m -> m | Error e -> fail e) manifest
  in
  List.iter
    (fun (p : Platform.t) ->
      Printf.printf "%s (%s, %s): %s\n" p.name p.family_name p.top_level
        (String.concat ", " (List.map (fun m -> m.name) (available p)));
      Option.iter
        (fun m -> match Manifest.validate m p with Ok _ -> () | Error e -> fail ~code:3 e)
        manifest)
    (Lazy.force Platform.builtin)

(* Binding every model of the platform proves its description against the trace. *)
let check p names path =
  let selected =
    match names with
    | [] -> available p
    | names ->
        List.map
          (fun n ->
            match List.find_opt (fun m -> m.name = n) (available p) with
            | Some m -> m
            | None -> fail ~code:2 (Printf.sprintf "platform %s has no model %s" p.name n))
          names
  in
  List.iter
    (fun m ->
      let tr = Hwfrp.Trace.open_file path in
      guard p (fun () ->
          let (Core.Any c) = Core.bind p tr ~model:m.name in
          m.build c;
          List.iter
            (Format.printf "%a@." Hwfrp.Bind.pp_report)
            (Hwfrp.Bind.check tr (Hwfrp.Bind.requirements c.net))))
    selected

open Cmdliner

let load name = match Platform.find name with Ok p -> p | Error e -> fail ~code:2 e

let platform_doc =
  "A built-in platform (see $(b,coralview platforms)) or a JSON description; a file with several \
   configurations takes $(i,FILE):$(i,CONFIG)."

let platform =
  Term.(
    const load
    $ Arg.(required & opt (some string) None & info [ "platform"; "p" ] ~docv:"P" ~doc:platform_doc))

let file = Arg.(required & pos 0 (some file) None & info [] ~docv:"FILE" ~doc:"A VCD or FST trace.")

let limit =
  Term.(
    const (Option.value ~default:max_int)
    $ Arg.(
        value & opt (some int) None & info [ "limit" ] ~docv:"N" ~doc:"Print at most $(docv) rows."))

let at =
  Arg.(
    value
    & opt (some int) None
    & info [ "at" ] ~docv:"CYCLE" ~doc:"Also print the storage as of $(docv).")

let from_cycle =
  Arg.(
    value
    & opt (some int) None
    & info [ "from-cycle" ] ~docv:"N" ~doc:"Print rows from cycle $(docv).")

let to_cycle =
  Arg.(
    value
    & opt (some int) None
    & info [ "to-cycle" ] ~docv:"N" ~doc:"Print rows up to cycle $(docv).")

let pc_of s =
  match
    int_of_string_opt (if String.length s > 2 && String.sub s 0 2 = "0x" then s else "0x" ^ s)
  with
  | Some pc -> pc
  | None -> fail ~code:2 ("--pc: not a hex PC: " ^ s)

let window =
  let make first last pcs =
    {
      w_first = Option.value first ~default:0;
      w_last = Option.value last ~default:max_int;
      w_pcs = List.map pc_of pcs;
    }
  in
  Term.(
    const make $ from_cycle $ to_cycle
    $ Arg.(
        value & opt_all string []
        & info [ "pc" ] ~docv:"HEX"
            ~doc:"Print only rows of this PC; repeatable. The whole trace is still processed."))

let features =
  Arg.(
    value
    & opt (some string) None
    & info [ "features" ] ~docv:"SPEC" ~doc:"Rivet target features for disassembly.")

let manifest =
  Arg.(
    value
    & opt (some file) None
    & info [ "manifest" ] ~docv:"FILE"
        ~doc:"The emulator archive's $(i,hardware-configurations.json), to check against.")

let profile =
  Arg.(
    value & opt int 0
    & info [ "profile" ] ~docv:"N" ~doc:"Print the $(docv) PCs with the most cycles charged.")

let region p = function
  | None -> fun _ -> ""
  | Some f -> (
      let m = match Manifest.load f with Ok m -> m | Error e -> fail ~code:2 e in
      match Manifest.validate m p with
      | Error e -> fail ~code:3 e
      | Ok c -> (
          fun addr ->
            match Manifest.region_of c addr with
            | Some r -> " (" ^ r.region ^ ")"
            | None -> " (unmapped)"))

let exits =
  Cmd.Exit.info 1 ~doc:"a relation failed."
  :: Cmd.Exit.info 2 ~doc:"an invalid description, or a model the platform has no block for."
  :: Cmd.Exit.info 3 ~doc:"the trace does not match the description: a signal is missing or wrong."
  :: Cmd.Exit.defaults

let cmd name doc term = Cmd.v (Cmd.info name ~doc ~exits) term

(* A model command: bind the platform, run, and turn binding errors into exit codes. *)
let model name doc term =
  cmd name doc Term.(const (fun p f path -> guard p (fun () -> f p path)) $ platform $ term $ file)

let commands =
  [
    cmd "probe" "Count the signals, timestamps and changes of a trace." Term.(const probe $ file);
    cmd "tree" "Print a trace's scopes, or one scope's variables."
      Term.(
        const (fun depth vars path scope -> tree ~depth ~vars path scope)
        $ Arg.(value & opt int 2 & info [ "depth" ] ~docv:"N" ~doc:"Scope levels to print.")
        $ Arg.(value & flag & info [ "vars" ] ~doc:"Print the scope's variables and widths.")
        $ file
        $ Arg.(
            value & pos 1 string ""
            & info [] ~docv:"SCOPE" ~doc:"A scope path, components separated by $(b,/)."));
    cmd "decode" "Disassemble instruction words."
      Term.(
        const decode $ features
        $ Arg.(non_empty & pos_all string [] & info [] ~docv:"HEXWORD" ~doc:"Instruction words."));
    cmd "platforms" "List the built-in platforms and the models their blocks allow."
      Term.(const platforms $ manifest);
    cmd "check" "Bind the models of a platform to a trace and report every signal."
      Term.(
        const check $ platform
        $ Arg.(
            value & opt_all string []
            & info [ "model" ] ~docv:"M" ~doc:"Check only this model; repeatable.")
        $ file);
    cmd "signals" "Print named signals over a window, per cycle or as raw value changes."
      Term.(
        const (fun p raw json changes fc tc ft tt path paths ->
            signals
              (fun () ->
                match p with
                | Some p -> load p
                | None -> fail ~code:2 "signals needs --platform, or --raw")
              ~raw ~json ~changes ~cycles:(fc, tc) ~times:(ft, tt) path paths)
        $ Arg.(
            value & opt (some string) None & info [ "platform"; "p" ] ~docv:"P" ~doc:platform_doc)
        $ Arg.(
            value & flag
            & info [ "raw" ] ~doc:"Print value changes at their timestamps, with no clock.")
        $ Arg.(value & flag & info [ "json" ] ~doc:"Print one JSON object per value.")
        $ Arg.(value & flag & info [ "changes" ] ~doc:"Print only values that changed.")
        $ from_cycle $ to_cycle
        $ Arg.(
            value
            & opt (some int64) None
            & info [ "from-time" ] ~docv:"T" ~doc:"With $(b,--raw), from timestamp $(docv).")
        $ Arg.(
            value
            & opt (some int64) None
            & info [ "to-time" ] ~docv:"T" ~doc:"With $(b,--raw), up to timestamp $(docv).")
        $ file
        $ Arg.(
            non_empty & pos_right 0 string []
            & info [] ~docv:"PATH" ~doc:"An absolute signal path, components separated by $(b,/)."));
    model "commits" "Retired instructions with values and per-instruction cycles."
      Term.(
        const (fun features window limit profile p path ->
            commits p features ~window limit profile path)
        $ features $ window $ limit $ profile);
    model "stalls" "Why each dispatch lane did not dispatch."
      Term.(const (fun profile p path -> stalls p profile path) $ profile);
    model "memory" "LSU data requests and faults, with PC, address and data."
      Term.(
        const (fun manifest window limit p path ->
            memory p ~region:(region p manifest) ~window limit path)
        $ manifest $ window $ limit);
    model "tiles" "VME tile register writes, by PC."
      Term.(const (fun limit p path -> tiles p limit path) $ limit);
    model "registers" "The x/f register files, related to writes, scoreboards and retirements."
      Term.(const (fun at limit p path -> registers p ~at limit path) $ at $ limit);
    model "vectors" "The vector register file, related to its writes and retirements."
      Term.(const (fun at limit p path -> vectors p ~at limit path) $ at $ limit);
    model "traps" "Faults, the CSR updates they cause and whether the handler ran."
      Term.(const traps);
    model "bench" "Time opening, decoding and sampling a trace."
      Term.(
        const (fun nodes p path -> Bench.run p ~nodes path)
        $ Arg.(
            value & opt int 300 & info [ "nodes" ] ~docv:"N" ~doc:"Nodes in the synthetic graph."));
  ]

let () =
  exit
    (Cmd.eval
       (Cmd.group
          (Cmd.info "coralview" ~exits
             ~doc:"Observe the Coral NPU from the waveforms of its RTL simulators")
          commands))
