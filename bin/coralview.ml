[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Coralview

(* Every exit says how the producer ended. *)
let exit code = Stdlib.exit (Driver.finish code)

let probe path =
  let { Vcd.header; simulation } = Hwfrp_native.parse_file path in
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

type elf = { file : string; symbols : Symbols.t }

(* What the options of a command say. The terms of a command return changes to the defaults; they are
   applied once every term is evaluated, and the result is passed down. *)
type options = {
  select : bool;  (** [--no-select] clears it. *)
  plan : (string * Hwfrp.Capture.plan Lazy.t) option;  (** [--plan FILE], read at the first run. *)
  origins : string list option;  (** The models a [run] builds, which the plan must have. *)
  elf : elf option;
      (** [--elf FILE]: the functions of the program, to name PCs and to find a function. *)
  between : (Window_marker.spec * int) option;
      (** The window [--between-pc], [--around-symbol] or [--entry] names. *)
  manifest : string option;  (** [--manifest FILE], for the platform's instruction set. *)
  annotate : string option;  (** [--annotate FILE]: labels for addresses, joined into the rows. *)
  profile_by : Text.profile_by;
  simulator : string option ref;
      (** What the trace's own header says of the simulator; set as a trace is opened, and shared by the
          copies of the options. *)
}

type setting = options -> options

let defaults () =
  {
    select = true;
    plan = None;
    origins = None;
    elf = None;
    between = None;
    manifest = None;
    annotate = None;
    profile_by = Text.Pc;
    simulator = ref None;
  }

(* [--plan FILE]: before the first sample, the signals a run tracks must be the plan's, for the origins it
   builds: the model of the command, or the models of [run]. *)
let gate env =
  match env.plan with
  | None -> None
  | Some (file, plan) ->
      Some
        (fun tr ~model ->
          let plan = Lazy.force plan in
          let origins = Option.value env.origins ~default:[ model ] in
          let planned = Hwfrp.Capture.origins plan in
          (match List.filter (fun o -> not (List.mem o planned)) origins with
          | [] -> ()
          | absent ->
              fail ~code:3
                (Printf.sprintf "the plan %s was made without --model %s (it has %s)" file
                   (String.concat ", --model " absent)
                   (String.concat ", " planned)));
          match Hwfrp.Capture.check plan ~origins tr with
          | Ok () -> ()
          | Error l ->
              fail ~code:3
                (String.concat "\n"
                   (Printf.sprintf "the trace does not match the plan %s:" file
                   :: List.map (fun e -> "  " ^ e) l)))

let load_plan file =
  lazy
    (match Hwfrp.Capture.of_file (In_channel.with_open_bin file In_channel.input_all) with
    | Ok plan -> plan
    | Error e -> fail ~code:2 (Printf.sprintf "%s: %s" file e)
    | exception Sys_error e -> fail ~code:2 e)

let pull env (type k e s)
    (module A : Analysis.S with type Config.t = k and type Event.t = e and type Summary.t = s)
    (cfg : k) p tr =
  Analysis.pull ?gate:(gate env) (module A) cfg p tr

let decoder features =
  match Coral_isa.Rivet_decode.create ?features () with
  | Ok d -> d
  | Error e ->
      prerr_endline ("invalid --features: " ^ e);
      exit 2

let decode features words =
  let d = decoder features in
  List.iter
    (fun w ->
      match Coral_isa.Rivet_decode.decode d (int_of_string ("0x" ^ w)) with
      | Ok s -> Printf.printf "%s  %s\n" w s
      | Error e -> Printf.printf "%s  error: %s\n" w e)
    words

let tree ~depth ~vars path scope =
  Hwfrp_native.with_parse_file path @@ fun { Vcd.header; _ } ->
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

let jsonl_window (w : Text.window) =
  if Text.windowed w then
    Some
      {
        Jsonl.first = w.first;
        last = (if w.last = max_int then None else Some w.last);
        pcs = w.pcs;
      }
  else None

(* The simulator is only what the trace's own header says; nothing is assumed. *)
let note_simulator env tr =
  env.simulator :=
    Option.map String.trim (Hwfrp.Trace.header tr).version
    |> Option.map (fun v -> if v = "" then None else Some v)
    |> Option.join

(* A trace read to its end closes itself; a reader that may stop early scopes it with [with_trace]. *)
let open_trace env path =
  let tr = Hwfrp_native.open_input ~select:env.select path in
  note_simulator env tr;
  tr

let with_trace env path f =
  Hwfrp_native.with_input ~select:env.select path (fun tr ->
      note_simulator env tr;
      f tr)

let banner_line ~platform ~simulator =
  Printf.sprintf "platform %s%s\n" platform
    (match simulator with Some v -> ", simulator " ^ v | None -> "")

let banner env (p : Platform.t) =
  print_string (banner_line ~platform:p.name ~simulator:!(env.simulator))

let print_banner env ppf (p : Platform.t) =
  Format.pp_print_string ppf (banner_line ~platform:p.name ~simulator:!(env.simulator))

let jsonl_header env ~model ~platform ~trace =
  { (Jsonl.header ~model ~platform ~trace) with simulator = !(env.simulator) }

(* [--between-pc A,B --nth N] and the other markers: the window is found in the retirements of the run
   that prints it. What is wrong with the markers is known before the run. *)
let marker env =
  Option.map
    (fun (spec, nth) ->
      match Window_marker.make spec ~nth (Option.map (fun e -> e.symbols) env.elf) with
      | Ok m -> m
      | Error (code, msg) -> fail ~code msg)
    env.between

let resolve_window marker (window : Text.window) commits =
  match marker with
  | None -> window
  | Some m -> (
      match Window_marker.resolve m window (Lazy.force commits) with
      | Ok w -> w
      | Error (code, msg) -> fail ~code msg)

(* [k] prints to the standard output for "-", else to the file [path]. *)
let with_ppf path k =
  if path = "-" then begin
    let ppf = Format.formatter_of_out_channel stdout in
    Fun.protect (fun () -> k ppf) ~finally:(fun () -> Format.pp_print_flush ppf ())
  end
  else begin
    let oc = open_out path in
    Fun.protect
      (fun () ->
        let ppf = Format.formatter_of_out_channel oc in
        Fun.protect (fun () -> k ppf) ~finally:(fun () -> Format.pp_print_flush ppf ()))
      ~finally:(fun () -> close_out oc)
  end

let annotation_labels env ~functions =
  match env.annotate with
  | None -> fun _ -> []
  | Some file -> (
      match Annotate.load ~functions file with
      | Ok a -> Annotate.labels a
      | Error e -> fail ~code:2 ("--annotate: " ^ e))

let elf_functions env name =
  match env.elf with
  | None when Annotate.is_hex8 name -> []
  | None -> fail ~code:2 ("--annotate: " ^ name ^ " needs --elf")
  | Some { symbols = t; _ } ->
      List.map (fun (f : Symbols.func) -> (f.address, f.size)) (Symbols.find t name)

let ctx env (p : Platform.t) ?(features = None) ?(region = Region.none) ?(window = Text.everything)
    ?(limit = max_int) ?(profile = 0) ?(legend = false) ?(note = fun ~pc:_ ~cycle:_ -> None) () =
  if env.profile_by = Text.Function && env.elf = None then
    fail ~code:2 "--profile-by function needs --elf";
  (* Without --features, the manifest's configuration of the platform says which instructions exist. *)
  let features, configuration =
    match (features, env.manifest) with
    | Some _, _ | None, None -> (features, None)
    | None, Some file -> (
        let m = match Manifest.load file with Ok m -> m | Error e -> fail ~code:2 e in
        match Manifest.find m p.name with
        | None -> (None, None)
        | Some c ->
            ( Some
                (Coral_isa.Rivet_decode.spec_of_extensions ~extensions:c.extensions
                   ~matrix:(c.tile_registers <> None)),
              Some c ))
  in
  let disasm =
    let d = decoder features in
    fun word ->
      let s = Coral_isa.Rivet_decode.disasm d word in
      match configuration with
      | Some c when String.starts_with ~prefix:".word" s -> (
          match Coral_isa.Rivet_decode.needs d word with
          | [] -> s
          | fs ->
              fail ~code:3
                (Printf.sprintf
                   "word %08x needs %s, which configuration %s of the manifest does not list \
                    (extensions: %s); name them with --features to override"
                   word (String.concat " or " fs) c.name (String.concat ", " c.extensions)))
      | _ -> s
  in
  let note =
    let labels = annotation_labels env ~functions:(elf_functions env) in
    fun ~pc ~cycle ->
      match (note ~pc ~cycle, labels pc) with
      | n, [] -> n
      | None, ls -> Some (String.concat "; " ls)
      | Some n, ls -> Some (String.concat "; " (n :: ls))
  in
  {
    Text.root = Vcd_types.Reference.to_string (Platform.root p);
    disasm;
    instruction_class =
      (let d = decoder features in
       fun word ->
         match Coral_isa.Rivet_decode.instruction d word with
         | Ok i -> Coral_isa.Iclass.(name (of_instruction i))
         | Error _ -> "unknown");
    symbol =
      (match env.elf with
      | None -> fun _ -> None
      | Some { symbols = t; _ } ->
          fun pc ->
            Option.map (fun ((f : Symbols.func), off) -> (f.name, off)) (Symbols.lookup t pc));
    profile_by = env.profile_by;
    region;
    window;
    limit;
    profile;
    legend;
    note;
  }

let opts_ctx env p ?legend ?note (o : Models.opts) =
  ctx env p ~features:o.features ~region:o.region ~window:o.window ~limit:o.limit ~profile:o.profile
    ?legend ?note ()

(* The vsetvli configuration of [disasm --vconfig] for each PC of the --elf, if there is one. *)
let static_vconfig env =
  match env.elf with
  | None -> fun _ -> None
  | Some { file; _ } -> (
      let data =
        try In_channel.with_open_bin file In_channel.input_all with Sys_error e -> fail ~code:2 e
      in
      match Disasm.listing (decoder None) Disasm.everything data with
      | Error _ -> fun _ -> None
      | Ok items ->
          let t = Hashtbl.create 256 in
          List.iter
            (function
              | Disasm.Line { address; vconfig = Some v; _ } -> Hashtbl.replace t address v
              | _ -> ())
            (Disasm.with_vconfig items);
          Hashtbl.find_opt t)

(* A converted analysis: text through its own view, or JSON lines with the rows the window and the
   limit select; the summary always covers the whole trace. A window that markers name, and the
   configurations of [--vector], are found in the same run as the rows: they are kept until it ends. *)
let analyze env name (o : Models.opts) ?legend ?(vector = false) (p : Platform.t) ~format path =
  let (Models.M { a = (module A); cfg; text; status; commit; _ }) =
    match Models.find name with Some m -> m | None -> fail ~code:2 ("no analysis " ^ name)
  in
  let notes = ref (fun ~pc:_ ~cycle:_ -> None) in
  let note = if vector then Some (fun ~pc ~cycle -> !notes ~pc ~cycle) else None in
  let ctx = opts_ctx env p ?legend ?note o in
  Driver.report_to (if format = `Jsonl then `Jsonl else `Text);
  let marker = marker env in
  let events, summary, diags, ctx =
    if Option.is_none marker && not vector then begin
      let pulled = guard p (fun () -> pull env (module A) (cfg o) p (open_trace env path)) in
      (pulled.events, pulled.summary, pulled.diags, ctx)
    end
    else begin
      let more = Option.is_some marker && commit = None in
      let env =
        {
          env with
          origins =
            Some
              ((if more then [ Commits.name ] else [])
              @ [ A.name ]
              @ if vector then [ Ops.name ] else []);
        }
      in
      let (events, summary, commits, ops), diags =
        guard p (fun () ->
            Pass.run ?gate:(gate env) p (open_trace env path) ~model:A.name
              {
                build =
                  (fun c ->
                    let commits = if more then Some (Pass.commits c) else None in
                    let rows = Pass.collect (module A) (cfg o) c in
                    let ops =
                      if vector then Some (Pass.collect (module Ops) Ops.Config.default c) else None
                    in
                    fun stats ->
                      let events, summary = rows stats in
                      ( events,
                        summary,
                        Option.map (fun r -> r stats) commits,
                        Option.map (fun r -> fst (r stats)) ops ));
              })
      in
      let commits =
        lazy
          (match (commit, commits) with
          | Some retirement, _ -> List.filter_map retirement events
          | None, Some l -> l
          | None, None -> [])
      in
      if vector then
        notes :=
          Vector_notes.notes ~static:(static_vconfig env) (Lazy.force commits)
            (List.filter_map
               (function Ops.Event.Op o -> Some o | Burst _ -> None)
               (Option.value ops ~default:[]));
      let ctx = { ctx with window = resolve_window marker ctx.window commits } in
      (List.to_seq events, (fun () -> summary), (fun () -> diags), ctx)
    end
  in
  (match format with
  | `Text ->
      with_ppf "-" (fun ppf ->
          print_banner env ppf p;
          Text.drain (text o ctx ppf summary) events)
  | `Jsonl ->
      let selected = Text.selected ctx.window in
      let keep e =
        selected ~cycle:(A.Event.cycle e) ~pc:(Option.value (A.Event.pc e) ~default:(-1))
      in
      Jsonl.write stdout
        {
          (jsonl_header env ~model:A.name ~platform:p.name ~trace:path) with
          window = jsonl_window ctx.window;
        }
        (module A)
        (Seq.take ctx.limit (Seq.filter keep events))
        ~diags summary);
  match status (summary ()) with 0 -> () | n -> exit n

let signals env platform ~raw ~format ~changes ~cycles:(from_cycle, to_cycle)
    ~times:(from_time, to_time) path paths =
  let jsonl = format = `Jsonl in
  Driver.report_to (if jsonl then `Jsonl else `Text);
  if raw && Option.is_some env.plan then
    fail ~code:2 "--plan checks the sampled signals, which --raw does not build: drop --raw";
  with_trace env path @@ fun tr ->
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
      let (p : Platform.t) =
        match platform with Some p -> p | None -> invalid_arg "signals: no platform"
      in
      if not jsonl then Signals.header p;
      ( Signals.sample_rule_name p.sample,
        fun ~changes f ->
          guard p (fun () ->
              Signals.sampled ?gate:(gate env) p tr paths
                ~from:(Option.value from_cycle ~default:0)
                ~until:(Option.value to_cycle ~default:max_int)
                ~changes f) )
    end
  in
  let samples = ref 0 in
  if jsonl then
    print_endline
      (Codec.to_line Jsonl.header_jsont
         (jsonl_header env ~model:Signals.model
            ~platform:
              (match platform with Some (p : Platform.t) when not raw -> p.name | _ -> "-")
            ~trace:path));
  let print (r : Signals.record) =
    incr samples;
    if jsonl then
      print_endline (Codec.to_line Signals.Event.jsont (Sample (Signals.sample ~phase r)))
    else Signals.row r
  in
  run ~changes print;
  if jsonl then print_endline (Codec.to_line Signals.Summary.jsont { samples = !samples })

let platforms manifests =
  let manifests =
    List.map (fun f -> match Manifest.load f with Ok m -> m | Error e -> fail e) manifests
  in
  List.iter
    (fun (p : Platform.t) ->
      Printf.printf "%s (%s, %s): %s\n" p.name p.family_name p.top_level
        (String.concat ", " (List.map Models.name (Models.available p)));
      if manifests <> [] then
        match List.find_opt (fun m -> Manifest.find m p.name <> None) manifests with
        | Some m -> ( match Manifest.validate m p with Ok _ -> () | Error e -> fail ~code:3 e)
        | None ->
            fail ~code:3
              (Printf.sprintf "platform %s: no configuration %s in the manifests" p.name p.name))
    (Lazy.force Platform.builtin)

(* Binding every model of the platform proves its description against the trace. *)
let select_models (p : Platform.t) = function
  | [] -> Models.available p
  | names ->
      List.map
        (fun n ->
          match Models.find n with
          | Some m -> m
          | None -> fail ~code:2 (Printf.sprintf "no model %s" n))
        names

let check env p names ~format path =
  let selected = select_models p names in
  let jsonl = format = `Jsonl and bound = ref 0 and failed = ref 0 in
  with_trace env path ignore;
  if not jsonl then banner env p;
  if jsonl then
    print_endline
      (Codec.to_line Jsonl.header_jsont
         (jsonl_header env ~model:"check" ~platform:p.name ~trace:path));
  List.iter
    (fun m ->
      with_trace env path @@ fun tr ->
      guard p (fun () ->
          let (Core.Any c) = Core.bind ~collect:true p tr ~model:(Models.name m) in
          Models.subscribe m c;
          List.iter
            (fun (r : Hwfrp.Bind.report) ->
              List.iter (fun e -> incr (if Hwfrp.Bind.ok e then bound else failed)) r.entries;
              if jsonl then
                List.iter
                  (fun e ->
                    print_endline (Codec.to_line Check.jsont (Check.of_entry r.model r.root e)))
                  r.entries
              else Format.printf "%a@." Hwfrp.Bind.pp_report r)
            (Hwfrp.Bind.report c.net)))
    selected;
  if jsonl then
    print_endline (Codec.to_line Check.summary_jsont { bound = !bound; failed = !failed });
  if !failed > 0 then
    fail ~code:3
      (Printf.sprintf "platform %s does not match the trace: %d of %d signals failed" p.name !failed
         (!bound + !failed))

(* The signals the models need of a catalog trace, to be recorded by a producer and checked by [--plan].
   Several catalogs (say, the FST and VCD builds of one simulator) must agree; the first is the one the
   producer's names are taken from. *)
let plan_command env (p : Platform.t) names signal_paths catalogs dir producer ~format =
  if catalogs = [] then fail ~code:2 "plan needs --catalog";
  let models = if names = [] && signal_paths <> [] then [] else select_models p names in
  let with_catalog file f =
    match Hwfrp_native.open_file_result file with
    | Ok tr -> Fun.protect ~finally:(fun () -> Hwfrp_native.close tr) (fun () -> f tr)
    | Error (`Io _ as e) -> fail ~code:2 (Vcd.Error.to_string e)
    | Error e -> raise (Vcd.Error.E e)
  in
  let plans =
    List.concat_map
      (fun file ->
        List.map
          (fun m ->
            with_catalog file @@ fun tr ->
            guard p (fun () ->
                let (Core.Any c) = Core.bind p tr ~model:(Models.name m) in
                Models.subscribe m c;
                Hwfrp.Capture.plan ~origin:(Models.name m) tr [ c.net ]))
          models
        @
        if signal_paths = [] then []
        else
          with_catalog file @@ fun tr ->
          try
            [
              guard p (fun () ->
                  Hwfrp.Capture.plan ~origin:Signals.model tr [ Signals.net p tr signal_paths ]);
            ]
          with Signals.Missing s -> fail ~code:3 ("no signal " ^ s ^ " in " ^ file))
      catalogs
  in
  let indent l = List.map (fun e -> "  " ^ e) l in
  let plan =
    match Hwfrp.Capture.union plans with
    | Ok plan -> plan
    | Error l -> fail ~code:3 (String.concat "\n" ("the catalogs disagree:" :: indent l))
  in
  let manifest =
    with_catalog (List.hd catalogs) @@ fun first ->
    match
      Hwfrp.Capture.Verilator.manifest ~catalog:first ~producer ~format:(Hwfrp.Trace.format first)
        plan
    with
    | Ok m -> m
    | Error l -> fail ~code:2 (String.concat "\n" ("cannot select by name:" :: indent l))
  in
  (if not (Sys.file_exists dir) then
     try Unix.mkdir dir 0o755
     with Unix.Unix_error (e, _, _) -> fail ~code:2 (dir ^ ": " ^ Unix.error_message e));
  let write name text =
    let path = Filename.concat dir name in
    try Out_channel.with_open_bin path (fun oc -> output_string oc text)
    with Sys_error e -> fail ~code:2 e
  in
  write "select" manifest;
  write "plan" (Hwfrp.Capture.to_file plan);
  let entries = Hwfrp.Capture.entries plan and origins = Hwfrp.Capture.origins plan in
  let selected =
    List.length
      (List.filter
         (fun l -> String.starts_with ~prefix:"select " l)
         (String.split_on_char '\n' manifest))
  in
  match format with
  | `Text ->
      Printf.printf "%d signals, %d names selected, for %s\n" (List.length entries) selected
        (String.concat ", " origins)
  | `Jsonl ->
      print_endline
        (Codec.to_line Jsonl.header_jsont
           (jsonl_header env ~model:"plan" ~platform:p.name ~trace:(List.hd catalogs)));
      List.iter
        (fun e -> print_endline (Codec.to_line Plan_view.signal_jsont (Plan_view.of_entry e)))
        entries;
      print_endline
        (Codec.to_line Plan_view.summary_jsont { signals = List.length entries; selected; origins })

open Cmdliner

let load name = match Platform.find name with Ok p -> p | Error e -> fail ~code:2 e

let platform_doc =
  "A built-in platform (see $(b,coralview platforms)) or a JSON description; a file with several \
   configurations takes $(i,FILE):$(i,CONFIG)."

let platform =
  Term.(
    const load
    $ Arg.(required & opt (some string) None & info [ "platform"; "p" ] ~docv:"P" ~doc:platform_doc))

(* A trace file, and the effect of [--no-select], which comes with every one. *)
let file : (string * setting) Term.t =
  Term.(
    const (fun no_select path ->
        (path, fun o -> if no_select then { o with select = false } else o))
    $ Arg.(
        value & flag
        & info [ "no-select" ]
            ~doc:
              "Decode the changes of every signal of the trace, not only of those the analysis \
               reads. The output is the same; for comparing timings.")
    $ Arg.(required & pos 0 (some file) None & info [] ~docv:"FILE" ~doc:"A VCD or FST trace."))

let plan_opt =
  Arg.(
    value
    & opt (some string) None
    & info [ "plan" ] ~docv:"FILE"
        ~doc:
          "A plan from $(b,coralview plan): fail before the first sample unless the trace holds \
           exactly the signals the plan has for what this command builds.")

let exec_opt =
  Arg.(
    value
    & opt (some string) None
    & info [ "exec" ] ~docv:"COMMAND"
        ~doc:
          "Run $(docv) with $(b,sh -c) as the producer of the trace, which is $(b,-): its \
           descriptor 3 is the VCD stream (a VCD simulator's $(b,--trace_fd=3)). How it ended, and \
           whether the stream was read to its end, is written after the results; a producer that \
           failed makes the exit status 4. Its output is the command's own, so redirect it.")

(* The trace, the plan it must satisfy and the command that produces it: started by [produce], once
   every term of the command is evaluated. *)
type source = { path : string; exec : string option; set : setting }

let traced =
  Term.(
    const (fun (path, select) plan exec ->
        if Option.is_some exec && path <> "-" then
          fail ~code:2 "--exec produces the trace: give - as the trace";
        let plan o =
          match plan with None -> o | Some f -> { o with plan = Some (f, load_plan f) }
        in
        { path; exec; set = (fun o -> plan (select o)) })
    $ file $ plan_opt $ exec_opt)

let produce src = Option.iter Driver.start src.exec

(* The settings of the terms of a command, applied in the order of the list. *)
let all (settings : setting Term.t list) : setting Term.t =
  List.fold_right
    (fun t rest -> Term.(const (fun set rest o -> rest (set o)) $ t $ rest))
    settings (Term.const Fun.id)

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

let elf : setting Term.t =
  let load file =
    match Symbols.load file with
    | Ok symbols -> Some { file; symbols }
    | Error e -> fail ~code:2 ("--elf: " ^ e)
  in
  Term.(
    const (fun f ->
        let elf = Option.bind f load in
        fun o -> { o with elf })
    $ Arg.(
        value
        & opt (some file) None
        & info [ "elf" ] ~docv:"FILE"
            ~doc:
              "The program's ELF: $(b,commits) shows $(i,function+offset) beside each PC, and \
               $(b,--profile-by function) groups by function."))

let window =
  Term.(
    const (fun first last pcs ->
        {
          Text.first = Option.value first ~default:0;
          last = Option.value last ~default:max_int;
          pcs = List.map pc_of pcs;
        })
    $ from_cycle $ to_cycle
    $ Arg.(
        value & opt_all string []
        & info [ "pc" ] ~docv:"HEX"
            ~doc:"Print only rows of this PC; repeatable. The whole trace is still processed."))

(* The window [--between-pc], [--around-symbol] or [--entry] names, found in the run. *)
let between : setting Term.t =
  let make between around entry nth =
    let between =
      match (between, around, entry) with
      | None, None, None -> None
      | Some (a, b), None, None -> Some (Window_marker.Between (a, b), nth)
      | None, Some name, None -> Some (Window_marker.Around name, nth)
      | None, None, Some name -> Some (Window_marker.Entry name, nth)
      | _ -> fail ~code:2 "--between-pc, --around-symbol and --entry are alternatives"
    in
    fun o -> { o with between }
  in
  let between =
    let pc_pair =
      Arg.conv
        ( (fun s ->
            match String.split_on_char ',' s with
            | [ a; b ] -> Ok (pc_of a, pc_of b)
            | _ -> Error (`Msg "expected two hex PCs, A,B")),
          fun ppf (a, b) -> Format.fprintf ppf "%x,%x" a b )
    in
    Arg.(
      value
      & opt (some pc_pair) None
      & info [ "between-pc" ] ~docv:"A,B"
          ~doc:
            "Print rows from the retirement of PC $(i,A) to the next retirement of PC $(i,B), both \
             included; they bound the window as $(b,--from-cycle) and $(b,--to-cycle) do, and are \
             found in the retirements of the run.")
  in
  let around =
    Arg.(
      value
      & opt (some string) None
      & info [ "around-symbol" ] ~docv:"NAME"
          ~doc:
            "Print rows from the retirement of the entry of function $(i,NAME) of the $(b,--elf) \
             to the first $(b,ret) retired inside it. Call depth is not tracked: a recursive \
             function ends at its innermost return, and one that leaves by a tail call has no end.")
  in
  let entry =
    Arg.(
      value
      & opt (some string) None
      & info [ "entry" ] ~docv:"NAME"
          ~doc:
            "Print rows from the first retirement of the entry of function $(i,NAME) of the \
             $(b,--elf) to the $(b,ret) that pops its frame (calls inside it nest), or to the end \
             of the trace if there is none: the startup before it is not counted.")
  in
  let nth =
    Arg.(
      value & opt int 1
      & info [ "nth" ] ~docv:"N"
          ~doc:
            "With $(b,--between-pc) or $(b,--entry), start at the $(docv)th retirement of the \
             start.")
  in
  Term.(const make $ between $ around $ entry $ nth)

let features =
  Arg.(
    value
    & opt (some string) None
    & info [ "features" ] ~docv:"SPEC"
        ~doc:
          "Rivet target features for disassembly; Rivet's default set plus \
           $(b,+xcoralzvt,+xcoralsys) when absent.")

let manifest : setting Term.t =
  Term.(
    const (fun manifest o -> { o with manifest })
    $ Arg.(
        value
        & opt (some file) None
        & info [ "manifest" ] ~docv:"FILE"
            ~doc:
              "The emulator archive's $(i,hardware-configurations.json), to check against. Without \
               $(b,--features) it also gives the instruction set: the platform's configuration \
               lists the extensions, and a word that needs another is an error naming it."))

let profile_by : setting Term.t =
  Term.(
    const (fun profile_by o -> { o with profile_by })
    $ Arg.(
        value
        & opt (enum [ ("pc", Text.Pc); ("class", Text.Class); ("function", Text.Function) ]) Text.Pc
        & info [ "profile-by" ] ~docv:"KEY"
            ~doc:
              "Group the $(b,--profile) of $(b,commits) by $(b,pc) (the default), instruction \
               $(b,class) (alu, fp, mem, branch, vector, vector-mem, tile or system) or \
               $(b,function) (needs $(b,--elf))."))

let profile =
  Arg.(
    value & opt int 0
    & info [ "profile" ] ~docv:"N"
        ~doc:"Print the $(docv) PCs (or classes, or functions) with the most cycles charged.")

let annotate_file =
  Arg.(
    value
    & opt (some file) None
    & info [ "annotate" ] ~docv:"FILE"
        ~doc:
          "Labels for addresses, one $(i,LOCATION LABEL) a line, joined into the rows as a \
           trailing comment. A location is $(b,NAME) (a whole function), $(b,NAME+OFF), \
           $(b,NAME+OFF-OFF) (offsets, the end exclusive) or $(b,0xADDR[-0xADDR]); names need an \
           ELF. Lines starting with # are skipped.")

let annotate : setting Term.t = Term.(const (fun annotate o -> { o with annotate }) $ annotate_file)

let legend =
  Arg.(
    value & flag
    & info [ "legend" ]
        ~doc:
          "Explain the columns of the row listing before it. The listing always has a header line.")

let regions env p =
  match env.manifest with
  | None -> Region.none
  | Some f -> (
      let m = match Manifest.load f with Ok m -> m | Error e -> fail ~code:2 e in
      match Manifest.validate m p with Error e -> fail ~code:3 e | Ok c -> Region.of_manifest c)

let format =
  Arg.(
    value
    & opt (enum [ ("text", `Text); ("jsonl", `Jsonl) ]) `Text
    & info [ "format" ] ~docv:"FORMAT"
        ~doc:
          "$(b,text), or $(b,jsonl): a header line, the selected events, the diagnostics and the \
           summary, one JSON object per line.")

let output =
  Arg.(
    value
    & opt (some string) None
    & info [ "output"; "o" ] ~docv:"FILE" ~doc:"Write to $(docv) instead of the standard output.")

(* Every print goes to the standard output, which then is the file. *)
let redirect = function
  | None -> ()
  | Some f ->
      let fd =
        try Unix.openfile f [ O_WRONLY; O_CREAT; O_TRUNC ] 0o644
        with Unix.Unix_error (e, _, _) -> fail ~code:2 (f ^ ": " ^ Unix.error_message e)
      in
      Unix.dup2 fd Unix.stdout;
      Unix.close fd

let exits =
  Cmd.Exit.info 1 ~doc:"a relation failed."
  :: Cmd.Exit.info 2 ~doc:"an invalid description, or a model the platform has no block for."
  :: Cmd.Exit.info 3
       ~doc:
         "the trace does not match the description (a signal is missing or wrong), or cannot be \
          read to its end."
  :: Cmd.Exit.defaults

let error_kind : Vcd.Error.error -> string = function
  | `Syntax _ -> "syntax"
  | `Incomplete _ -> "incomplete"
  | `Fst _ -> "fst"
  | `Io _ -> "io"
  | `Not_fst _ -> "not fst"
  | `Closed _ -> "closed"
  | `Superseded _ -> "superseded"
  | `Encoding _ -> "encoding"

let cmd name doc term = Cmd.v (Cmd.info name ~doc ~exits) term

(* A model command: bind the platform, run, and turn binding errors into exit codes. [opts] are the
   settings its terms return; the producer, if any, starts after they are all evaluated. *)
let model ?(opts = []) name doc term =
  cmd name doc
    Term.(
      const (fun p set f src ->
          let env = src.set (set (defaults ())) in
          produce src;
          guard p (fun () -> f env p src.path))
      $ platform $ all opts $ term $ traced)

(* A text view's destination in [run]. The standard output is written as the views go only when one
   view alone prints to it: otherwise the text is held until the view ends, so that the views do not
   interleave. *)
type text_out = {
  ppf : Format.formatter;
  finish : unit -> unit;  (** Flushes and releases it; the held text goes out. *)
  abandon : unit -> unit;  (** The same without the held text, after an error. *)
}

let text_out path ~hold =
  let finished = ref false in
  let make ppf ~flush ~release ~abandon =
    {
      ppf;
      finish =
        (fun () ->
          if not !finished then begin
            finished := true;
            Format.pp_print_flush ppf ();
            flush ();
            release ()
          end);
      abandon =
        (fun () ->
          if not !finished then begin
            finished := true;
            Format.pp_print_flush ppf ();
            abandon ()
          end);
    }
  in
  if path <> "-" then
    let oc = open_out path in
    make
      (Format.formatter_of_out_channel oc)
      ~flush:ignore
      ~release:(fun () -> close_out oc)
      ~abandon:(fun () -> close_out_noerr oc)
  else if hold then
    let buf = Buffer.create 4096 in
    make (Format.formatter_of_buffer buf) ~flush:ignore
      ~release:(fun () -> print_string (Buffer.contents buf))
      ~abandon:ignore
  else
    make
      (Format.formatter_of_out_channel stdout)
      ~flush:(fun () -> flush stdout)
      ~release:ignore ~abandon:ignore

(* Several analyses in one pass: each is built in the same net, and its events are pushed to its
   sinks as they come. A model without a sink prints its text to the standard output. *)
let run_models env (p : Platform.t) (o : Models.opts) models sinks ?perfetto ?kanata ?report path =
  let sinks =
    List.map
      (fun s ->
        match String.split_on_char ':' s with
        | m :: kind :: rest when List.mem kind [ "text"; "jsonl" ] ->
            (m, kind, String.concat ":" rest)
        | _ -> fail ~code:2 ("--sink " ^ s ^ ": expected MODEL:text:PATH or MODEL:jsonl:PATH"))
      sinks
  in
  let models =
    List.sort_uniq compare
      (models @ List.map (fun (m, _, _) -> m) sinks @ if kanata = None then [] else [ "commits" ])
  in
  if models = [] then fail ~code:2 "run needs --model or --sink";
  (let on_stdout = List.filter (fun (_, _, f) -> f = "-") sinks in
   Driver.report_to
     (match on_stdout with
     | (_, "jsonl", _) :: _ -> `Jsonl
     | (_, _, _) :: _ -> `Text
     | [] ->
         if sinks = [] && perfetto = None && kanata = None && report = None then `Text else `Stderr));
  let ctx = opts_ctx env p o in
  let marker = marker env in
  let env =
    {
      env with
      origins =
        Some
          (if Option.is_none marker then models else List.sort_uniq compare (Commits.name :: models));
    }
  in
  let tr = open_trace env path in
  let (Core.Any c) = Core.bind p tr ~model:"run" in
  let targets m =
    match List.filter (fun (m', _, _) -> m' = m) sinks with
    | [] when perfetto <> None || kanata <> None || report <> None -> []
    | [] -> [ ("text", "-") ]
    | l -> List.map (fun (_, k, f) -> (k, f)) l
  in
  let on_stdout k =
    List.concat_map (fun m -> List.filter (fun (k', f) -> k' = k && f = "-") (targets m)) models
  in
  let hold = List.length (on_stdout "text") > 1 || on_stdout "jsonl" <> [] in
  let outs = ref [] in
  let diags_written = ref false in
  Fun.protect ~finally:(fun () -> List.iter (fun o -> o.abandon ()) !outs) @@ fun () ->
  let tracked = guard p (fun () -> Option.map (fun _ -> Pass.commits c) marker) in
  let finishers =
    guard p (fun () ->
        List.map
          (fun m ->
            match Models.find m with
            | None -> fail ~code:2 ("run: no analysis " ^ m)
            | Some (M { a = (module A); cfg; text; status; perfetto = view; _ }) ->
                let mine = targets m in
                (* What depends on the window: with markers, after the run has found it. *)
                let setup (ctx : Text.ctx) =
                  let selected = Text.selected ctx.window in
                  let keep e =
                    selected ~cycle:(A.Event.cycle e)
                      ~pc:(Option.value (A.Event.pc e) ~default:(-1))
                  in
                  let jsonl =
                    List.filter_map
                      (fun (k, f) ->
                        if k <> "jsonl" then None
                        else begin
                          let oc = if f = "-" then stdout else open_out f in
                          output_string oc
                            (Codec.to_line Jsonl.header_jsont
                               {
                                 (jsonl_header env ~model:A.name ~platform:p.name ~trace:path) with
                                 window = jsonl_window ctx.window;
                               });
                          output_char oc '\n';
                          Some (oc, ref 0)
                        end)
                      mine
                  in
                  let summary_of =
                    ref (fun () -> failwith "run: the summary is read after the run")
                  in
                  let late () = !summary_of () in
                  let texts =
                    List.filter_map
                      (fun (k, f) ->
                        if k <> "text" then None
                        else begin
                          let out = text_out f ~hold in
                          outs := out :: !outs;
                          print_banner env out.ppf p;
                          Some (out, text o ctx out.ppf late)
                        end)
                      mine
                  in
                  let section =
                    Option.map
                      (fun _ ->
                        let ctx =
                          {
                            ctx with
                            limit = 0;
                            profile = (if ctx.profile = 0 then 10 else ctx.profile);
                          }
                        in
                        let buf = Buffer.create 1024 in
                        let ppf = Format.formatter_of_buffer buf in
                        (buf, ppf, text o ctx ppf late))
                      report
                  in
                  let events = ref [] in
                  let collect = perfetto <> None && view <> None in
                  let add e =
                    if collect then events := e :: !events;
                    List.iter (fun (_, (sink : _ Text.sink)) -> sink.add e) texts;
                    Option.iter (fun (_, _, (sink : _ Text.sink)) -> sink.add e) section;
                    if keep e then
                      List.iter
                        (fun (oc, n) ->
                          if !n < ctx.limit then begin
                            incr n;
                            output_string oc (Codec.to_line A.Event.jsont e);
                            output_char oc '\n'
                          end)
                        jsonl
                  in
                  let finish s =
                    (summary_of := fun () -> s);
                    List.iter
                      (fun (oc, _) ->
                        if not !diags_written then begin
                          diags_written := true;
                          Seq.iter
                            (fun d ->
                              output_string oc (Codec.to_line Codec.diag d);
                              output_char oc '\n')
                            (Hwfrp.Diag.stream c.net)
                        end;
                        output_string oc (Codec.to_line A.Summary.jsont s);
                        output_char oc '\n';
                        if oc == stdout then flush oc else close_out oc)
                      jsonl;
                    List.iter
                      (fun ((out : text_out), (sink : _ Text.sink)) ->
                        sink.finish ();
                        out.finish ())
                      texts;
                    let section =
                      Option.map
                        (fun (buf, ppf, (sink : _ Text.sink)) ->
                          sink.finish ();
                          Format.pp_print_flush ppf ();
                          (A.name, A.doc, Buffer.contents buf))
                        section
                    in
                    ( status s,
                      (match (perfetto, view) with
                      | Some _, Some v -> [ v ctx (List.to_seq (List.rev !events)) s ]
                      | _ -> []),
                      section )
                  in
                  (add, finish)
                in
                let live = if Option.is_none marker then Some (setup ctx) else None in
                let held = ref [] in
                let summary =
                  Analysis.subscribe
                    (module A)
                    (cfg o) c
                    (fun e -> match live with Some (add, _) -> add e | None -> held := e :: !held)
                in
                fun stats ctx ->
                  let s = summary stats in
                  let _, finish =
                    match live with
                    | Some l -> l
                    | None ->
                        let ((add, _) as l) = setup ctx in
                        List.iter add (List.rev !held);
                        l
                  in
                  finish s)
          models)
  in
  let kanata_out =
    Option.map
      (fun f ->
        (* Written as the run goes, to the standard output too unless something else prints there. *)
        let hold =
          Option.is_some marker
          || f = "-"
             && (on_stdout "text" <> []
                || on_stdout "jsonl" <> []
                || perfetto = Some "-" || report = Some "-")
        in
        let buf = Buffer.create 4096 in
        let dest = lazy (if f = "-" then stdout else open_out f) in
        let put = if hold then Buffer.add_string buf else output_string (Lazy.force dest) in
        let builder = Kanata.Builder.create ~disasm:ctx.disasm (Kanata.Writer.create put) in
        guard p (fun () ->
            let (_ : Hwfrp.Sched.run_stats -> _) =
              Analysis.subscribe (module Commits) () c (Kanata.Builder.commit builder)
            in
            if List.mem "dispatch" (Platform.blocks p) then
              let (_ : Hwfrp.Sched.run_stats -> _) =
                Analysis.subscribe (module Stalls) () c (Kanata.Builder.stall builder)
              in
              ());
        (builder, dest, buf, hold))
      kanata
  in
  let stats = Core.run ?gate:(gate env) c in
  let ctx =
    {
      ctx with
      window =
        resolve_window marker ctx.window
          (lazy (match tracked with Some r -> r stats | None -> []));
    }
  in
  let results = List.map (fun f -> f stats ctx) finishers in
  Option.iter
    (fun (builder, dest, buf, hold) ->
      Kanata.Builder.finish builder;
      let oc = Lazy.force dest in
      if hold then output_string oc (Buffer.contents buf);
      if oc != stdout then close_out oc else flush oc)
    kanata_out;
  Option.iter
    (fun f ->
      let oc = if f = "-" then stdout else open_out f in
      Perfetto.write oc (List.concat_map (fun (_, v, _) -> v) results);
      if oc != stdout then close_out oc)
    perfetto;
  Option.iter
    (fun f ->
      let oc = if f = "-" then stdout else open_out f in
      Printf.fprintf oc
        {|# coralview report

| | |
|---|---|
| platform | %s |
| trace | %s |
| root | %s |
| cycles | %d |
| models | %s |
|}
        p.name path ctx.root (Core.cycles c stats) (String.concat ", " models);
      List.iter
        (fun (_, _, section) ->
          Option.iter
            (fun (name, doc, body) ->
              Printf.fprintf oc "\n## %s\n\n%s\n\n```text\n%s```\n" name doc body)
            section)
        results;
      if oc != stdout then close_out oc else flush oc)
    report;
  match List.fold_left (fun n (k, _, _) -> max n k) 0 results with 0 -> () | n -> exit n

(* A saved JSONL back to the text its model prints: the events and summary decoded with the
   model's codecs, then its text view. *)
let read_jsonl file =
  let first =
    In_channel.with_open_text file In_channel.input_line
    |> Option.to_result ~none:"empty file"
    |> Fun.flip Result.bind (Codec.of_line Jsonl.header_jsont)
  in
  match first with Ok h -> h | Error e -> fail ~code:2 (file ^ ": " ^ e)

(* The events of a saved JSONL, decoded with the model's codecs, and its summary, which follows them:
   it is read once the events are exhausted. *)
let with_jsonl (type e s) (module A : Analysis.S with type Event.t = e and type Summary.t = s) file
    k =
  In_channel.with_open_text file (fun ic ->
      let summary = ref None in
      let events =
        Seq.filter_map
          (fun (i, line) ->
            match line with
            | Ok (Jsonl.Event e) -> Some e
            | Ok (Summary s) ->
                summary := Some s;
                None
            | Ok (Header _ | Diag _) -> None
            | Error e -> fail ~code:2 (Printf.sprintf "%s:%d: %s" file (i + 1) e))
          (Seq.mapi (fun i l -> (i, l)) (Jsonl.read (module A) ic))
      in
      k events (fun () ->
          match !summary with None -> fail ~code:2 (file ^ ": no summary") | Some s -> s))

let entry file (h : Jsonl.header) =
  match Models.find h.model with
  | Some e -> e
  | None -> fail ~code:2 (file ^ ": no analysis " ^ h.model)

(* A saved JSONL back to the text its model prints. *)
let render env p o file =
  let h = read_jsonl file in
  let (M { a = (module A); text; status; _ }) = entry file h in
  let s =
    with_jsonl
      (module A)
      file
      (fun events summary ->
        with_ppf "-" (fun ppf ->
            Format.pp_print_string ppf (banner_line ~platform:h.platform ~simulator:h.simulator);
            Text.drain (text o (opts_ctx env p o) ppf summary) events);
        summary ())
  in
  match status s with 0 -> () | n -> exit n

(* The profile of a saved JSONL, as its model's --profile prints it. *)
let profile_of env p o file =
  let h = read_jsonl file in
  match entry file h with
  | M { a = (module A); profile = Some profile; _ } ->
      with_jsonl
        (module A)
        file
        (fun events summary ->
          with_ppf "-" (fun ppf -> Text.drain (profile (opts_ctx env p o) ppf summary) events))
  | M _ -> fail ~code:2 (file ^ ": " ^ h.model ^ " has no profile")

let saved_platform =
  Arg.(
    value
    & opt (some string) None
    & info [ "platform"; "p" ] ~docv:"P"
        ~doc:"The platform, when the file's is not built in: as for the analyses.")

let disasm features sections functions range no_padding vconfig summary annotate format output path
    =
  redirect output;
  let d = decoder features in
  let data =
    try In_channel.with_open_bin path In_channel.input_all with Sys_error e -> fail ~code:2 e
  in
  match Disasm.listing d { Disasm.sections; functions; range } data with
  | Error e -> fail ~code:2 (path ^ ": " ^ e)
  | Ok items -> (
      let items = if no_padding then Disasm.collapse_padding items else items in
      let items = if vconfig then Disasm.with_vconfig items else items in
      let items =
        match annotate with
        | None -> items
        | Some file -> (
            let functions name =
              match Symbols.of_string data with
              | Ok t ->
                  List.map (fun (f : Symbols.func) -> (f.address, f.size)) (Symbols.find t name)
              | Error _ -> []
            in
            match Annotate.load ~functions file with
            | Ok a -> Disasm.with_annotations (Annotate.labels a) items
            | Error e -> fail ~code:2 ("--annotate: " ^ e))
      in
      match (summary, format) with
      | true, `Text -> Format.printf "%a@?" Disasm.pp_summary (Disasm.summary items)
      | true, `Jsonl -> fail ~code:2 "--summary prints text only"
      | false, `Text -> Format.printf "%a@?" Disasm.pp_text items
      | false, `Jsonl ->
          List.iter
            (function
              | Disasm.Line l -> print_endline (Codec.to_line Disasm.line_jsont l)
              | Padding { address; words } ->
                  print_endline (Codec.to_line Disasm.padding_jsont (address, words))
              | Label _ -> ())
            items)

let range_conv =
  let parse s =
    match String.split_on_char '-' s with
    | [ lo; hi ] -> (
        match (int_of_string_opt lo, int_of_string_opt hi) with
        | Some lo, Some hi when lo <= hi -> Ok (lo, hi)
        | _ -> Error (`Msg "expected LO-HI, hexadecimal with 0x or decimal, LO <= HI"))
    | _ -> Error (`Msg "expected LO-HI")
  in
  Arg.conv (parse, fun ppf (lo, hi) -> Format.fprintf ppf "0x%x-0x%x" lo hi)

let jsonl_file = Arg.(required & pos 0 (some file) None & info [] ~docv:"FILE" ~doc:"A JSONL file.")

let beats =
  Arg.(
    value & opt int 0 & info [ "beats" ] ~docv:"N" ~doc:"Print the first $(docv) beats of each job.")

let pair_conv =
  Arg.conv
    ( (fun s ->
        match String.split_on_char ',' s with
        | [ x ] -> Ok (x, x)
        | [ x; y ] -> Ok (x, y)
        | _ -> Error (`Msg "expected A or A,B")),
      fun ppf (x, y) -> Format.fprintf ppf "%s,%s" x y )

let nonneg =
  Arg.conv
    ( (fun s ->
        match int_of_string_opt s with
        | Some n when n >= 0 -> Ok n
        | Some _ -> Error (`Msg (s ^ " is negative; expected N >= 0"))
        | None -> Error (`Msg (s ^ " is not an integer"))),
      Format.pp_print_int )

let commands =
  [
    cmd "probe" "Count the signals, timestamps and changes of a trace."
      Term.(const (fun (path, _) -> probe path) $ file);
    cmd "tree" "Print a trace's scopes, or one scope's variables."
      Term.(
        const (fun depth vars (path, _) scope -> tree ~depth ~vars path scope)
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
    cmd "disasm" "Disassemble the code of an RV32 ELF."
      Term.(
        const disasm $ features
        $ Arg.(
            value & opt_all string []
            & info [ "section" ] ~docv:"NAME"
                ~doc:"List only this executable section; repeatable. All of them by default.")
        $ Arg.(
            value & opt_all string []
            & info [ "function" ] ~docv:"NAME"
                ~doc:
                  "List only the extent of this function symbol; repeatable. Needs a symbol table.")
        $ Arg.(
            value
            & opt (some range_conv) None
            & info [ "range" ] ~docv:"LO-HI"
                ~doc:"List only addresses in [LO, HI); hexadecimal with 0x, or decimal.")
        $ Arg.(
            value & flag
            & info [ "no-padding" ]
                ~doc:
                  "Print each run of two or more zero words as one line (a $(b,padding_words) \
                   object in JSONL).")
        $ Arg.(
            value & flag
            & info [ "vconfig" ]
                ~doc:
                  "Note each vector instruction's static configuration (SEW, LMUL, AVL) from the \
                   vsetvli words that reach it, as a trailing comment ($(b,vconfig) in JSONL).")
        $ Arg.(
            value & flag
            & info [ "summary" ]
                ~doc:
                  "Print the instruction count by class for each $(b,FUNC) symbol instead of the \
                   listing.")
        $ annotate_file
        $ Arg.(
            value
            & opt (enum [ ("text", `Text); ("jsonl", `Jsonl) ]) `Text
            & info [ "format" ] ~docv:"FORMAT"
                ~doc:
                  "$(b,text), or $(b,jsonl): one object per instruction with its address, word, \
                   spelling, mnemonic, class, enclosing symbol and branch target.")
        $ output
        $ Arg.(required & pos 0 (some file) None & info [] ~docv:"FILE" ~doc:"An RV32 ELF."));
    cmd "compare"
      "Two runs of one kernel side by side: the summaries of their windows and the instructions \
       whose cycles differ most."
      Term.(
        const (fun p elf around entry top loops format output a b ->
            redirect output;
            (match (around, entry) with
            | Some _, Some _ -> fail ~code:2 "--around-symbol and --entry are alternatives"
            | _ -> ());
            let pick = function Some (x, y) -> (Some x, Some y) | None -> (None, None) in
            let elf_a, elf_b = pick elf in
            let marker_of f = function Some name -> Some (f name, 1) | None -> None in
            let shared = { (defaults ()) with simulator = ref None } in
            let side trace elf name_of =
              let elf =
                Option.map
                  (fun f ->
                    match Symbols.load f with
                    | Ok symbols -> { file = f; symbols }
                    | Error e -> fail ~code:2 ("--elf: " ^ e))
                  elf
              in
              let name, entry_only = name_of in
              let between =
                match around with
                | Some _ -> marker_of (fun n -> Window_marker.Around n) name
                | None ->
                    if entry_only then marker_of (fun n -> Window_marker.Entry n) name else None
              in
              let env = { shared with elf; between } in
              let c = ctx env p () in
              let marker = marker env in
              let window = ref c.window in
              let summary, commits =
                guard p (fun () ->
                    Window_summary.analyze ?gate:(gate env) p
                      ~window:(fun commits ->
                        window := resolve_window marker c.window (lazy commits);
                        !window)
                      (open_trace env trace))
              in
              let base =
                match (name, elf) with
                | Some n, Some { symbols = t; _ } when around <> None || entry_only -> (
                    match Symbols.find t n with [ f ] -> f.address | _ -> 0)
                | _ -> 0
              in
              { Compare.trace; summary; window = !window; commits; base; disasm = c.disasm }
            in
            let names =
              match (around, entry) with
              | Some x, _ | None, Some x -> pick (Some x)
              | _ -> (None, None)
            in
            let entry_only = entry <> None in
            let sa = side a elf_a (fst names, entry_only) in
            let sb = side b elf_b (snd names, entry_only) in
            match format with
            | `Text ->
                banner shared p;
                Compare.text ~top sa sb;
                if loops then Compare.text_loops ~top sa sb
            | `Jsonl ->
                print_endline
                  (Codec.to_line Jsonl.header_jsont
                     (jsonl_header shared ~model:"compare" ~platform:p.name ~trace:(a ^ "," ^ b)));
                print_endline (Codec.to_line Compare.summary_jsont (sa.summary, sb.summary));
                List.iter
                  (fun r -> print_endline (Codec.to_line Compare.row_jsont r))
                  (Compare.rows ~top sa sb);
                if loops then
                  List.iter
                    (fun r -> print_endline (Codec.to_line Compare.loop_row_jsont r))
                    (Compare.loop_rows ~top sa sb))
        $ platform
        $ Arg.(
            value
            & opt (some pair_conv) None
            & info [ "elf" ] ~docv:"A[,B]"
                ~doc:"The program's ELF of each run, or of both when one is given.")
        $ Arg.(
            value
            & opt (some pair_conv) None
            & info [ "around-symbol" ] ~docv:"NA[,NB]"
                ~doc:
                  "Compare the window from the entry of function $(i,NA) of the first run to its \
                   first $(b,ret), and of $(i,NB) of the second (the same name for both when one \
                   is given). Differences are by offset from the function's entry.")
        $ Arg.(
            value
            & opt (some pair_conv) None
            & info [ "entry" ] ~docv:"NA[,NB]"
                ~doc:
                  "As $(b,--around-symbol), but to the $(b,ret) that pops the entry's frame (calls \
                   inside it nest), or to the end of that trace if there is none.")
        $ Arg.(
            value & opt nonneg 10
            & info [ "top" ] ~docv:"N" ~doc:"Print the $(docv) largest per-instruction differences.")
        $ Arg.(
            value & flag
            & info [ "loops" ]
                ~doc:
                  "Also pair the loops of the two windows by rank of their cycles, for kernels \
                   whose instructions do not line up by offset (up to $(b,--top) pairs).")
        $ format $ output
        $ Arg.(required & pos 0 (some file) None & info [] ~docv:"A" ~doc:"The first trace.")
        $ Arg.(required & pos 1 (some file) None & info [] ~docv:"B" ~doc:"The second trace."));
    cmd "platforms" "List the built-in platforms and the models their blocks allow."
      Term.(
        const platforms
        $ Arg.(
            value & opt_all file []
            & info [ "manifest" ] ~docv:"FILE"
                ~doc:
                  "An archive's $(i,hardware-configurations.json); repeatable. Every platform must \
                   be in one of them and match it."));
    cmd "check" "Bind the models of a platform to a trace and report every signal."
      Term.(
        const (fun p names format output (path, select) ->
            redirect output;
            check (select (defaults ())) p names ~format path)
        $ platform
        $ Arg.(
            value & opt_all string []
            & info [ "model" ] ~docv:"M" ~doc:"Check only this model; repeatable.")
        $ format $ output $ file);
    cmd "plan"
      "Plan the signals some analyses need of a catalog trace, and the names a producer selects."
      Term.(
        const (fun p names signals catalogs dir producer format ->
            plan_command (defaults ()) p names signals catalogs dir producer ~format)
        $ platform
        $ Arg.(
            value & opt_all string []
            & info [ "model" ] ~docv:"M"
                ~doc:
                  "Plan this model; repeatable. By default every model of the platform, unless \
                   $(b,--signal) is given.")
        $ Arg.(
            value & opt_all string []
            & info [ "signal" ] ~docv:"PATH"
                ~doc:
                  "Also plan this signal as $(b,coralview signals) would read it, with the \
                   platform's clock; repeatable.")
        $ Arg.(
            value & opt_all string []
            & info [ "catalog" ] ~docv:"FILE"
                ~doc:
                  "A trace of the simulator build, whose events are not read; repeatable. The \
                   first gives the producer's names, the others must agree with it.")
        $ Arg.(
            required
            & opt (some string) None
            & info [ "o"; "out" ] ~docv:"DIR"
                ~doc:"Write $(i,DIR)/select, for the simulator, and $(i,DIR)/plan, for $(b,--plan).")
        $ Arg.(
            value & opt string "coralnpu-sim"
            & info [ "producer" ] ~docv:"NAME"
                ~doc:"The simulator's name, recorded in the manifest.")
        $ format);
    cmd "signals" "Print named signals over a window, per cycle or as raw value changes."
      Term.(
        const (fun p raw json format output changes fc tc ft tt src paths ->
            let platform =
              if raw then None
              else
                match p with
                | Some p -> Some (load p)
                | None -> fail ~code:2 "signals needs --platform, or --raw"
            in
            let env = src.set (defaults ()) in
            produce src;
            redirect output;
            signals env platform ~raw
              ~format:(if json then `Jsonl else format)
              ~changes ~cycles:(fc, tc) ~times:(ft, tt) src.path paths)
        $ Arg.(
            value & opt (some string) None & info [ "platform"; "p" ] ~docv:"P" ~doc:platform_doc)
        $ Arg.(
            value & flag
            & info [ "raw" ] ~doc:"Print value changes at their timestamps, with no clock.")
        $ Arg.(value & flag & info [ "json" ] ~doc:"The same as $(b,--format jsonl).")
        $ format $ output
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
        $ traced
        $ Arg.(
            non_empty & pos_right 0 string []
            & info [] ~docv:"PATH" ~doc:"An absolute signal path, components separated by $(b,/)."));
    model
      ~opts:[ elf; between; manifest; profile_by; annotate ]
      "commits" "Retired instructions with values and per-instruction cycles."
      Term.(
        const (fun features window limit profile legend vector format output env p path ->
            redirect output;
            if vector && format = `Jsonl then fail ~code:2 "--vector is for the text listing";
            analyze env "commits"
              { Models.default with features; window; limit; profile }
              ~legend ~vector p ~format path)
        $ features $ window $ limit $ profile $ legend
        $ Arg.(
            value & flag
            & info [ "vector" ]
                ~doc:
                  "Append to each vector instruction's row the SEW, LMUL and $(b,vl) the RVV \
                   backend ran it under (the $(b,ops) model), and the $(b,disasm --vconfig) one \
                   with $(b,--elf) where they differ. Text only.")
        $ format $ output);
    model ~opts:[ elf; between; profile_by ] "stalls" Stalls.doc
      Term.(
        const (fun window profile format output env p path ->
            redirect output;
            analyze env "stalls" { Models.default with window; profile } p ~format path)
        $ window $ profile $ format $ output);
    model ~opts:[ elf; between; manifest ] "memory" Memory.doc
      Term.(
        const (fun window limit format output env p path ->
            let region = regions env p in
            redirect output;
            analyze env "memory" { Models.default with region; window; limit } p ~format path)
        $ window $ limit $ format $ output);
    model ~opts:[ elf; between; manifest ] "cost"
      "Retired instructions by class and memory region: commits joined with memory."
      Term.(
        const (fun window format output env p path ->
            let region = regions env p in
            redirect output;
            let c = ctx env p ~region ~window () in
            let marker = marker env in
            let env = { env with origins = Some [ Commits.name; Memory.name ] } in
            let (commits, accesses), _ =
              Pass.run ?gate:(gate env) p (open_trace env path) ~model:Commits.name
                {
                  build =
                    (fun c ->
                      let commits = Pass.collect (module Commits) () c in
                      let accesses = Pass.collect (module Memory) { region } c in
                      fun stats ->
                        ( Commits.commits (fst (commits stats)),
                          List.filter_map
                            (function
                              | Memory.Event.Access a -> Some a | Fault _ | Unmatched _ -> None)
                            (fst (accesses stats)) ));
                }
            in
            let window = resolve_window marker c.window (lazy commits) in
            let rows = Cost.join ~classify:c.instruction_class ~window commits accesses in
            match format with
            | `Text ->
                banner env p;
                Cost.text rows
            | `Jsonl ->
                print_endline
                  (Codec.to_line Jsonl.header_jsont
                     {
                       (jsonl_header env ~model:"cost" ~platform:p.name ~trace:path) with
                       window = jsonl_window window;
                     });
                List.iter (fun r -> print_endline (Codec.to_line Cost.row_jsont r)) rows)
        $ window $ format $ output);
    model ~opts:[ elf; between; manifest ] "summary"
      "Instructions, cycles, data requests, vector operations and stall reasons of a window."
      Term.(
        const (fun window format output env p path ->
            let region = regions env p in
            redirect output;
            let c = ctx env p ~region ~window () in
            let marker = marker env in
            let window = ref c.window in
            let s, _ =
              guard p (fun () ->
                  Window_summary.analyze ?gate:(gate env) p
                    ~window:(fun commits ->
                      window := resolve_window marker c.window (lazy commits);
                      !window)
                    ~region (open_trace env path))
            in
            let window = !window in
            match format with
            | `Text ->
                banner env p;
                Window_summary.text s
            | `Jsonl ->
                print_endline
                  (Codec.to_line Jsonl.header_jsont
                     {
                       (jsonl_header env ~model:"summary" ~platform:p.name ~trace:path) with
                       window = jsonl_window window;
                     });
                print_endline (Codec.to_line Window_summary.jsont s))
        $ window $ format $ output);
    model ~opts:[ elf; between; manifest ] "loops"
      "Loops from backward branches: trips, instructions and cycles a trip, cycles by PC."
      Term.(
        const (fun features window format output env p path ->
            redirect output;
            let c = ctx env p ~features ~window () in
            let marker = marker env in
            let commits, _ =
              guard p (fun () ->
                  Pass.run ?gate:(gate env) p (open_trace env path) ~model:Commits.name
                    { build = Pass.commits })
            in
            let window = resolve_window marker c.window (lazy commits) in
            (* Only the cycle range: a PC filter would cut the trips apart. *)
            let commits =
              List.filter
                (fun (k : Commits.commit) -> k.retired >= window.first && k.retired <= window.last)
                commits
            in
            let loops = Loops.detect commits in
            match format with
            | `Text ->
                banner env p;
                Loops.text ~disasm:c.disasm ~symbol:c.symbol loops
            | `Jsonl ->
                print_endline
                  (Codec.to_line Jsonl.header_jsont
                     {
                       (jsonl_header env ~model:"loops" ~platform:p.name ~trace:path) with
                       window = jsonl_window window;
                     });
                List.iter (fun l -> print_endline (Codec.to_line Loops.loop_jsont l)) loops)
        $ features $ window $ format $ output);
    model
      ~opts:[ elf; between; manifest; profile_by ]
      "axi" Axi.doc
      Term.(
        const (fun features window limit profile format output env p path ->
            let region = regions env p in
            redirect output;
            analyze env "axi"
              { Models.default with features; region; window; limit; profile }
              p ~format path)
        $ features $ window $ limit $ profile $ format $ output);
    model ~opts:[ manifest ] "dma" Dma.doc
      Term.(
        const (fun beats format output env p path ->
            let region = regions env p in
            redirect output;
            analyze env "dma" { Models.default with region; beats } p ~format path)
        $ Arg.(
            value & opt int 0
            & info [ "beats" ] ~docv:"N" ~doc:"Print the first $(docv) beats of each job.")
        $ format $ output);
    model ~opts:[ elf; between ] "tiles" Tiles.doc
      Term.(
        const (fun window limit format output env p path ->
            redirect output;
            analyze env "tiles" { Models.default with window; limit } p ~format path)
        $ window $ limit $ format $ output);
    model ~opts:[ elf; between; profile_by ] "ops" Ops.doc
      Term.(
        const (fun features gap peak_window window limit profile format output env p path ->
            redirect output;
            analyze env "ops"
              { Models.default with window; limit; profile; ops = { gap; peak_window; features } }
              p ~format path)
        $ features
        $ Arg.(
            value & opt int Ops.Config.default.gap
            & info [ "gap" ] ~docv:"N"
                ~doc:"End a burst after $(docv) cycles with no vector arithmetic dispatched.")
        $ Arg.(
            value
            & opt int Ops.Config.default.peak_window
            & info [ "peak-window" ] ~docv:"N" ~doc:"Take the peak rate over $(docv) cycles.")
        $ window $ limit $ profile $ format $ output);
    model "registers" Registers.doc
      Term.(
        const (fun at limit format output env p path ->
            redirect output;
            analyze env "registers" { Models.default with at; limit } p ~format path)
        $ at $ limit $ format $ output);
    model "vectors" Vectors.doc
      Term.(
        const (fun at limit format output env p path ->
            redirect output;
            analyze env "vectors" { Models.default with at; limit } p ~format path)
        $ at $ limit $ format $ output);
    model "traps" Traps.doc
      Term.(
        const (fun format output env p path ->
            redirect output;
            analyze env "traps" Models.default p ~format path)
        $ format $ output);
    cmd "run" "Run several analyses in one pass over a trace, each to its own text or JSONL sinks."
      Term.(
        const
          (fun
            p models sinks perfetto kanata report features set window limit profile at beats src ->
            let env = src.set (set (defaults ())) in
            produce src;
            run_models env p ?perfetto ?kanata ?report
              {
                Models.default with
                region = regions env p;
                features;
                window;
                limit;
                profile;
                at;
                beats;
              }
              models sinks src.path)
        $ platform
        $ Arg.(
            value & opt_all string []
            & info [ "model"; "m" ] ~docv:"M"
                ~doc:"An analysis to run; repeatable. Without a sink it prints text.")
        $ Arg.(
            value & opt_all string []
            & info [ "sink" ] ~docv:"M:KIND:PATH"
                ~doc:
                  "Send analysis $(i,M) as $(b,text) or $(b,jsonl) to $(i,PATH), $(b,-) for the \
                   standard output; repeatable. The diagnostics of the shared net go into the \
                   first $(b,jsonl) sink only.")
        $ Arg.(
            value
            & opt (some string) None
            & info [ "perfetto" ] ~docv:"FILE"
                ~doc:
                  "Also write the transactions, DMA jobs and stall spans of the analyses run as a \
                   Chrome trace, for ui.perfetto.dev; a model without a sink then prints nothing.")
        $ Arg.(
            value
            & opt (some string) None
            & info [ "kanata" ] ~docv:"FILE"
                ~doc:
                  "Also write the retired instructions, with their stalls before dispatch, as a \
                   Kanata log for Konata.")
        $ Arg.(
            value
            & opt (some string) None
            & info [ "report" ] ~docv:"FILE"
                ~doc:
                  "Also write a Markdown report: each analysis' summary and profile (10 rows \
                   unless $(b,--profile)), without its rows.")
        $ features
        $ all [ elf; between; manifest; profile_by ]
        $ window $ limit $ profile $ at $ beats $ traced);
    cmd "render" "Print a saved JSONL of an analysis as the text its command prints."
      Term.(
        const (fun platform features set window limit profile at beats file ->
            let p = load (Option.value platform ~default:(read_jsonl file).platform) in
            let env = set (defaults ()) in
            render env p
              {
                Models.default with
                region = regions env p;
                features;
                window;
                limit;
                profile;
                at;
                beats;
              }
              file)
        $ saved_platform $ features
        $ all [ elf; between; manifest; profile_by ]
        $ window $ limit $ profile $ at $ beats $ jsonl_file);
    cmd "profile" "Print the profile of a saved JSONL of commits, stalls or axi."
      Term.(
        const (fun platform features n file ->
            let p = load (Option.value platform ~default:(read_jsonl file).platform) in
            profile_of (defaults ()) p { Models.default with features; profile = n } file)
        $ saved_platform $ features
        $ Arg.(
            value & opt int 10 & info [ "rows"; "n" ] ~docv:"N" ~doc:"The $(docv) heaviest rows.")
        $ jsonl_file);
    model "bench" "Time opening, decoding and sampling a trace."
      Term.(
        const (fun nodes env p path -> Bench.run p ~select:env.select ~nodes path)
        $ Arg.(
            value & opt int 300 & info [ "nodes" ] ~docv:"N" ~doc:"Nodes in the synthetic graph."));
  ]

let () =
  exit
    (match
       Cmd.eval ~catch:false
         (Cmd.group
            (Cmd.info "coralview" ~exits
               ~doc:"Observe the Coral NPU from the waveforms of its RTL simulators")
            commands)
     with
    | code -> code
    | exception Vcd.Error.E e ->
        flush stdout;
        prerr_endline
          (Printf.sprintf "coralview: trace read failed (%s): %s" (error_kind e)
             (Vcd.Error.to_string e));
        3
    | exception e ->
        flush stdout;
        prerr_endline ("coralview: internal error, uncaught exception:\n" ^ Printexc.to_string e);
        Cmd.Exit.internal_error)
