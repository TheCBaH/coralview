[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Coralview

(* Set by --no-select, which comes with every FILE. *)
let select = ref true

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

(* [--plan FILE]: before the first sample, the signals a run tracks must be the plan's, for the origins it
   builds: the model of the command, or the models of [run]. *)
let plan_path : string option ref = ref None
let run_origins : string list option ref = ref None

let () =
  let loaded = ref None in
  Core.gate :=
    fun tr ~model ->
      match !plan_path with
      | None -> ()
      | Some file -> (
          let plan =
            match !loaded with
            | Some plan -> plan
            | None ->
                let plan =
                  match
                    Hwfrp.Capture.of_file (In_channel.with_open_bin file In_channel.input_all)
                  with
                  | Ok plan -> plan
                  | Error e -> fail ~code:2 (Printf.sprintf "%s: %s" file e)
                  | exception Sys_error e -> fail ~code:2 e
                in
                loaded := Some plan;
                plan
          in
          let origins = Option.value !run_origins ~default:[ model ] in
          match Hwfrp.Capture.check plan ~origins tr with
          | Ok () -> ()
          | Error l ->
              fail ~code:3
                (String.concat "\n"
                   (Printf.sprintf "the trace does not match the plan %s:" file
                   :: List.map (fun e -> "  " ^ e) l)))

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

let selected = Text.selected

(* A converted analysis: text through its own view, or JSON lines with the rows the window and the
   limit select; the summary always covers the whole trace. *)
let analyze (type k e s)
    (module A : Analysis.S with type Config.t = k and type Event.t = e and type Summary.t = s)
    (cfg : k) (p : Platform.t) ?(status = fun _ -> 0) ~format ~(ctx : Text.ctx)
    (text : Text.ctx -> e list -> s -> unit) path =
  let pulled =
    guard p (fun () -> Analysis.pull (module A) cfg p (Hwfrp.Trace.open_input ~select:!select path))
  in
  (match format with
  | `Text -> text ctx (List.of_seq pulled.events) (pulled.summary ())
  | `Jsonl ->
      let keep e =
        selected ctx.window ~cycle:(A.Event.cycle e) ~pc:(Option.value (A.Event.pc e) ~default:(-1))
      in
      Jsonl.write stdout
        (Jsonl.header ~model:A.name ~platform:p.name ~trace:path)
        (module A)
        (Seq.take ctx.limit (Seq.filter keep pulled.events))
        ~diags:pulled.diags pulled.summary);
  match status (pulled.summary ()) with 0 -> () | n -> exit n

let ctx p ?(features = None) ?(region = Region.none) ?(window = Text.everything) ?(limit = max_int)
    ?(profile = 0) () =
  {
    Text.root = Vcd_types.Reference.to_string (Platform.root p);
    disasm = Coral_isa.Rivet_decode.disasm (decoder features);
    region;
    window;
    limit;
    profile;
  }

let signals platform ~raw ~format ~changes ~cycles:(from_cycle, to_cycle)
    ~times:(from_time, to_time) path paths =
  let jsonl = format = `Jsonl in
  if raw && !plan_path <> None then
    fail ~code:2 "--plan checks the sampled signals, which --raw does not build: drop --raw";
  let tr = Hwfrp.Trace.open_input ~select:!select path in
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
      if not jsonl then Signals.header p;
      ( Signals.sample_rule_name p.sample,
        fun ~changes f ->
          guard p (fun () ->
              Signals.sampled p tr paths
                ~from:(Option.value from_cycle ~default:0)
                ~until:(Option.value to_cycle ~default:max_int)
                ~changes f) )
    end
  in
  let samples = ref 0 in
  if jsonl then
    print_endline
      (Codec.to_line Jsonl.header_jsont
         (Jsonl.header ~model:Signals.model
            ~platform:(if raw then "-" else (platform ()).name)
            ~trace:path));
  let print (r : Signals.record) =
    incr samples;
    if jsonl then
      print_endline (Codec.to_line Signals.Event.jsont (Sample (Signals.sample ~phase r)))
    else Signals.row r
  in
  run ~changes print;
  if jsonl then print_endline (Codec.to_line Signals.Summary.jsont { samples = !samples })

type model = { name : string; about : string; needs : string list; build : 'c. 'c Core.t -> unit }

let models =
  [
    {
      name = Commits.name;
      about = "retired instructions with values and per-instruction cycles";
      needs = Commits.needs;
      build =
        (fun c ->
          ignore (Analysis.subscribe (module Commits) () c ignore : Hwfrp.Sched.run_stats -> _));
    };
    {
      name = Stalls.name;
      about = "why each dispatch lane did not dispatch, per cycle";
      needs = Stalls.needs;
      build =
        (fun c ->
          ignore (Analysis.subscribe (module Stalls) () c ignore : Hwfrp.Sched.run_stats -> _));
    };
    {
      name = Memory.name;
      about = "LSU data accesses with PC, address and data";
      needs = Memory.needs;
      build =
        (fun c ->
          ignore
            (Analysis.subscribe (module Memory) Memory.Config.default c ignore
              : Hwfrp.Sched.run_stats -> _));
    };
    {
      name = Axi.name;
      about = "AXI master transactions: all external traffic, pinned to its originators";
      needs = Axi.needs;
      build =
        (fun c ->
          ignore
            (Analysis.subscribe (module Axi) Axi.Config.default c ignore
              : Hwfrp.Sched.run_stats -> _));
    };
    {
      name = Dma.name;
      about = "DMA engine jobs: activation, descriptors, beats, completion";
      needs = Dma.needs;
      build =
        (fun c ->
          ignore
            (Analysis.subscribe (module Dma) Dma.Config.default c ignore
              : Hwfrp.Sched.run_stats -> _));
    };
    {
      name = Registers.model;
      about = "x/f register files: storage, scoreboard and retired state related";
      needs = Registers.needs;
      build =
        (fun c ->
          ignore
            (Analysis.subscribe (module Registers) Registers.Config.default c ignore
              : Hwfrp.Sched.run_stats -> _));
    };
    {
      name = Tiles.name;
      about = "VME tile register writes, by PC";
      needs = Tiles.needs;
      build =
        (fun c ->
          ignore (Analysis.subscribe (module Tiles) () c ignore : Hwfrp.Sched.run_stats -> _));
    };
    {
      name = Ops.name;
      about = "vector operations at the RVV backend's dispatch";
      needs = Ops.needs;
      build =
        (fun c ->
          ignore
            (Analysis.subscribe (module Ops) Ops.Config.default c ignore
              : Hwfrp.Sched.run_stats -> _));
    };
    {
      name = Traps.name;
      about = "faults, the CSR updates they cause and whether the handler ran";
      needs = Traps.needs;
      build =
        (fun c ->
          ignore (Analysis.subscribe (module Traps) () c ignore : Hwfrp.Sched.run_stats -> _));
    };
    {
      name = Vectors.model;
      about = "vector register file: storage related to its write ports";
      needs = Vectors.needs;
      build =
        (fun c ->
          ignore
            (Analysis.subscribe (module Vectors) Vectors.Config.default c ignore
              : Hwfrp.Sched.run_stats -> _));
    };
  ]

let available p =
  List.filter (fun m -> List.for_all (fun b -> List.mem b (Platform.blocks p)) m.needs) models

let platforms manifests =
  let manifests =
    List.map (fun f -> match Manifest.load f with Ok m -> m | Error e -> fail e) manifests
  in
  List.iter
    (fun (p : Platform.t) ->
      Printf.printf "%s (%s, %s): %s\n" p.name p.family_name p.top_level
        (String.concat ", " (List.map (fun m -> m.name) (available p)));
      if manifests <> [] then
        match List.find_opt (fun m -> Manifest.find m p.name <> None) manifests with
        | Some m -> ( match Manifest.validate m p with Ok _ -> () | Error e -> fail ~code:3 e)
        | None ->
            fail ~code:3
              (Printf.sprintf "platform %s: no configuration %s in the manifests" p.name p.name))
    (Lazy.force Platform.builtin)

(* Binding every model of the platform proves its description against the trace. *)
let select_models (p : Platform.t) = function
  | [] -> available p
  | names ->
      List.map
        (fun n ->
          match List.find_opt (fun m -> m.name = n) models with
          | Some m -> m
          | None -> fail ~code:2 (Printf.sprintf "no model %s" n))
        names

let check p names ~format path =
  let selected = select_models p names in
  let jsonl = format = `Jsonl and bound = ref 0 and failed = ref 0 in
  if jsonl then
    print_endline
      (Codec.to_line Jsonl.header_jsont (Jsonl.header ~model:"check" ~platform:p.name ~trace:path));
  List.iter
    (fun m ->
      let tr = Hwfrp.Trace.open_file ~select:!select path in
      guard p (fun () ->
          let (Core.Any c) = Core.bind p tr ~model:m.name in
          m.build c;
          List.iter
            (fun (r : Hwfrp.Bind.report) ->
              if jsonl then
                List.iter
                  (fun e ->
                    let b = Check.of_entry r.model r.root e in
                    incr (if Check.ok b then bound else failed);
                    print_endline (Codec.to_line Check.jsont b))
                  r.entries
              else Format.printf "%a@." Hwfrp.Bind.pp_report r)
            (Hwfrp.Bind.check tr (Hwfrp.Bind.requirements c.net))))
    selected;
  if jsonl then
    print_endline (Codec.to_line Check.summary_jsont { bound = !bound; failed = !failed })

(* The signals the models need of a catalog trace, to be recorded by a producer and checked by [--plan].
   Several catalogs (say, the FST and VCD builds of one simulator) must agree; the first is the one the
   producer's names are taken from. *)
let plan_command (p : Platform.t) names signal_paths catalogs dir producer ~format =
  if catalogs = [] then fail ~code:2 "plan needs --catalog";
  let models = if names = [] && signal_paths <> [] then [] else select_models p names in
  let catalog file = try Hwfrp.Trace.open_file file with Sys_error e -> fail ~code:2 e in
  let plans =
    List.concat_map
      (fun file ->
        List.map
          (fun m ->
            let tr = catalog file in
            guard p (fun () ->
                let (Core.Any c) = Core.bind p tr ~model:m.name in
                m.build c;
                Hwfrp.Capture.plan ~origin:m.name tr [ c.net ]))
          models
        @
        if signal_paths = [] then []
        else
          let tr = catalog file in
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
  let first = catalog (List.hd catalogs) in
  let manifest =
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
           (Jsonl.header ~model:"plan" ~platform:p.name ~trace:(List.hd catalogs)));
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

let file =
  Term.(
    const (fun no_select path ->
        if no_select then select := false;
        path)
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

(* The trace, and the plan it must satisfy. *)
let traced =
  Term.(
    const (fun path plan ->
        plan_path := plan;
        path)
    $ file $ plan_opt)

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
      Text.first = Option.value first ~default:0;
      last = Option.value last ~default:max_int;
      pcs = List.map pc_of pcs;
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
    & info [ "features" ] ~docv:"SPEC"
        ~doc:
          "Rivet target features for disassembly; Rivet's default set plus $(b,+xcoralzvt) when \
           absent.")

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

let regions p = function
  | None -> Region.none
  | Some f -> (
      let m = match Manifest.load f with Ok m -> m | Error e -> fail ~code:2 e in
      match Manifest.validate m p with Error e -> fail ~code:3 e | Ok c -> Region.of_manifest c)

let region p m = Region.suffix (regions p m)

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
      let fd = Unix.openfile f [ O_WRONLY; O_CREAT; O_TRUNC ] 0o644 in
      Unix.dup2 fd Unix.stdout;
      Unix.close fd

let exits =
  Cmd.Exit.info 1 ~doc:"a relation failed."
  :: Cmd.Exit.info 2 ~doc:"an invalid description, or a model the platform has no block for."
  :: Cmd.Exit.info 3 ~doc:"the trace does not match the description: a signal is missing or wrong."
  :: Cmd.Exit.defaults

let cmd name doc term = Cmd.v (Cmd.info name ~doc ~exits) term

(* A model command: bind the platform, run, and turn binding errors into exit codes. *)
let model name doc term =
  cmd name doc
    Term.(const (fun p f path -> guard p (fun () -> f p path)) $ platform $ term $ traced)

(* What [coralview run] needs of an analysis: its config and text view from the common options. *)
type opts = {
  o_region : Region.t;
  o_features : string option;
  o_window : Text.window;
  o_limit : int;
  o_profile : int;
  o_at : int option;
  o_beats : int;
}

type entry =
  | E : {
      a : (module Analysis.S with type Config.t = 'k and type Event.t = 'e and type Summary.t = 's);
      cfg : opts -> 'k;
      text : opts -> Text.ctx -> 'e list -> 's -> unit;
      status : 's -> int;
      profile : (Text.ctx -> 'e list -> 's -> unit) option;
      perfetto : (Text.ctx -> 'e list -> 's -> Perfetto.process) option;
    }
      -> entry

let entries =
  let plain text _ = text and ok _ = 0 and profile = None and perfetto = None in
  [
    ( "commits",
      E
        {
          a = (module Commits);
          cfg = (fun _ -> ());
          text = plain Commits.text;
          status = ok;
          profile = Some Commits.profile;
          perfetto;
        } );
    ( "stalls",
      E
        {
          a = (module Stalls);
          cfg = (fun _ -> ());
          text = plain Stalls.text;
          status = ok;
          profile = Some Stalls.profile;
          perfetto = Some Stalls.perfetto;
        } );
    ( "memory",
      E
        {
          a = (module Memory);
          cfg = (fun o -> { region = o.o_region });
          text = plain Memory.text;
          status = ok;
          profile;
          perfetto;
        } );
    ( "axi",
      E
        {
          a = (module Axi);
          cfg = (fun o -> { region = o.o_region });
          text = plain Axi.text;
          status = ok;
          profile = Some Axi.profile;
          perfetto = Some Axi.perfetto;
        } );
    ( "dma",
      E
        {
          a = (module Dma);
          cfg = (fun o -> { region = o.o_region });
          text = (fun o -> Dma.text ~beats:o.o_beats);
          status = ok;
          profile;
          perfetto = Some Dma.perfetto;
        } );
    ( "tiles",
      E
        {
          a = (module Tiles);
          cfg = (fun _ -> ());
          text = plain Tiles.text;
          profile;
          perfetto;
          status = ok;
        } );
    ( "ops",
      E
        {
          a = (module Ops);
          cfg = (fun _ -> Ops.Config.default);
          text = plain Ops.text;
          status = ok;
          profile = Some Ops.profile;
          perfetto = Some Ops.perfetto;
        } );
    ( "registers",
      E
        {
          a = (module Registers);
          cfg = (fun o -> { at = o.o_at });
          text = plain Registers.text;
          status = Registers.status;
          profile;
          perfetto;
        } );
    ( "vectors",
      E
        {
          a = (module Vectors);
          cfg = (fun o -> { at = o.o_at });
          text = plain Vectors.text;
          status = Vectors.status;
          profile;
          perfetto;
        } );
    ( "traps",
      E
        {
          a = (module Traps);
          cfg = (fun _ -> ());
          text = plain Traps.text;
          profile;
          perfetto;
          status = ok;
        } );
  ]

(* Prints of [f] go to [path], or to the standard output for "-". *)
let printing_to path f =
  if path = "-" then f ()
  else begin
    flush stdout;
    let saved = Unix.dup Unix.stdout in
    let fd = Unix.openfile path [ O_WRONLY; O_CREAT; O_TRUNC ] 0o644 in
    Unix.dup2 fd Unix.stdout;
    Unix.close fd;
    Fun.protect f ~finally:(fun () ->
        flush stdout;
        Unix.dup2 saved Unix.stdout;
        Unix.close saved)
  end

(* Several analyses in one pass: each is built in the same net, and its events are pushed to its
   sinks as they come. A model without a sink prints its text to the standard output. *)
let run_models (p : Platform.t) o models sinks ?perfetto ?kanata ?report path =
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
  let ctx =
    ctx p ~features:o.o_features ~region:o.o_region ~window:o.o_window ~limit:o.o_limit
      ~profile:o.o_profile ()
  in
  run_origins := Some models;
  let tr = Hwfrp.Trace.open_input ~select:!select path in
  let (Core.Any c) = Core.bind p tr ~model:"run" in
  let finishers =
    guard p (fun () ->
        List.map
          (fun m ->
            match List.assoc_opt m entries with
            | None -> fail ~code:2 ("run: no analysis " ^ m)
            | Some (E { a = (module A); cfg; text; status; perfetto = view; _ }) ->
                let mine =
                  match List.filter (fun (m', _, _) -> m' = m) sinks with
                  | [] when perfetto <> None || kanata <> None || report <> None -> []
                  | [] -> [ ("text", "-") ]
                  | l -> List.map (fun (_, k, f) -> (k, f)) l
                in
                let keep e =
                  selected ctx.window ~cycle:(A.Event.cycle e)
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
                             (Jsonl.header ~model:A.name ~platform:p.name ~trace:path));
                        output_char oc '\n';
                        Some (oc, ref 0)
                      end)
                    mine
                in
                let texts =
                  List.filter_map (fun (k, f) -> if k = "text" then Some f else None) mine
                in
                let events = ref [] in
                let summary =
                  Analysis.subscribe
                    (module A)
                    (cfg o) c
                    (fun e ->
                      if texts <> [] || report <> None || (perfetto <> None && view <> None) then
                        events := e :: !events;
                      if keep e then
                        List.iter
                          (fun (oc, n) ->
                            if !n < ctx.limit then begin
                              incr n;
                              output_string oc (Codec.to_line A.Event.jsont e);
                              output_char oc '\n'
                            end)
                          jsonl)
                in
                fun stats ->
                  let s = summary stats in
                  List.iter
                    (fun (oc, _) ->
                      Seq.iter
                        (fun d ->
                          output_string oc (Codec.to_line Codec.diag d);
                          output_char oc '\n')
                        (Hwfrp.Diag.stream c.net);
                      output_string oc (Codec.to_line A.Summary.jsont s);
                      output_char oc '\n';
                      if oc == stdout then flush oc else close_out oc)
                    jsonl;
                  let events = List.rev !events in
                  List.iter (fun f -> printing_to f (fun () -> text o ctx events s)) texts;
                  let section =
                    Option.map
                      (fun _ ->
                        let tmp = Filename.temp_file "coralview" ".txt" in
                        let ctx =
                          {
                            ctx with
                            limit = 0;
                            profile = (if ctx.profile = 0 then 10 else ctx.profile);
                          }
                        in
                        printing_to tmp (fun () -> text o ctx events s);
                        let body = In_channel.with_open_text tmp In_channel.input_all in
                        Sys.remove tmp;
                        (A.name, A.doc, body))
                      report
                  in
                  ( status s,
                    (match (perfetto, view) with Some _, Some v -> [ v ctx events s ] | _ -> []),
                    section ))
          models)
  in
  let kanata_events =
    Option.map
      (fun _ ->
        let commits = ref [] and stalls = ref [] in
        guard p (fun () ->
            let (_ : Hwfrp.Sched.run_stats -> _) =
              Analysis.subscribe (module Commits) () c (fun e -> commits := e :: !commits)
            in
            if List.mem "dispatch" (Platform.blocks p) then
              let (_ : Hwfrp.Sched.run_stats -> _) =
                Analysis.subscribe (module Stalls) () c (fun e -> stalls := e :: !stalls)
              in
              ());
        (commits, stalls))
      kanata
  in
  let stats = Core.run c in
  let results = List.map (fun f -> f stats) finishers in
  Option.iter
    (fun f ->
      let commits, stalls = Option.get kanata_events in
      let oc = if f = "-" then stdout else open_out f in
      Kanata.write oc (Kanata.of_run ~disasm:ctx.disasm (List.rev !commits) (List.rev !stalls));
      if oc != stdout then close_out oc)
    kanata;
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
        p.name path ctx.root stats.ticks.(0) (String.concat ", " models);
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

(* The events and summary of a saved JSONL, decoded with the model's codecs. *)
let decode_jsonl (type e s) (module A : Analysis.S with type Event.t = e and type Summary.t = s)
    file =
  let events = ref [] and summary = ref None in
  In_channel.with_open_text file (fun ic ->
      Seq.iteri
        (fun i -> function
          | Ok (Jsonl.Event e) -> events := e :: !events
          | Ok (Summary s) -> summary := Some s
          | Ok (Header _ | Diag _) -> ()
          | Error e -> fail ~code:2 (Printf.sprintf "%s:%d: %s" file (i + 1) e))
        (Jsonl.read (module A) ic));
  match !summary with
  | None -> fail ~code:2 (file ^ ": no summary")
  | Some s -> (List.rev !events, s)

let entry file (h : Jsonl.header) =
  match List.assoc_opt h.model entries with
  | Some e -> e
  | None -> fail ~code:2 (file ^ ": no analysis " ^ h.model)

let opts_ctx p o =
  ctx p ~features:o.o_features ~region:o.o_region ~window:o.o_window ~limit:o.o_limit
    ~profile:o.o_profile ()

(* A saved JSONL back to the text its model prints. *)
let render p o file =
  let (E { a = (module A); text; status; _ }) = entry file (read_jsonl file) in
  let events, s = decode_jsonl (module A) file in
  text o (opts_ctx p o) events s;
  match status s with 0 -> () | n -> exit n

(* The profile of a saved JSONL, as its model's --profile prints it. *)
let profile_of p o file =
  let h = read_jsonl file in
  match entry file h with
  | E { a = (module A); profile = Some profile; _ } ->
      let events, s = decode_jsonl (module A) file in
      profile (opts_ctx p o) events s
  | E _ -> fail ~code:2 (file ^ ": " ^ h.model ^ " has no profile")

let saved_platform =
  Arg.(
    value
    & opt (some string) None
    & info [ "platform"; "p" ] ~docv:"P"
        ~doc:"The platform, when the file's is not built in: as for the analyses.")

let jsonl_file = Arg.(required & pos 0 (some file) None & info [] ~docv:"FILE" ~doc:"A JSONL file.")

let beats =
  Arg.(
    value & opt int 0 & info [ "beats" ] ~docv:"N" ~doc:"Print the first $(docv) beats of each job.")

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
        const (fun p names format output path ->
            redirect output;
            check p names ~format path)
        $ platform
        $ Arg.(
            value & opt_all string []
            & info [ "model" ] ~docv:"M" ~doc:"Check only this model; repeatable.")
        $ format $ output $ file);
    cmd "plan"
      "Plan the signals some analyses need of a catalog trace, and the names a producer selects."
      Term.(
        const (fun p names signals catalogs dir producer format ->
            plan_command p names signals catalogs dir producer ~format)
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
        const (fun p raw json format output changes fc tc ft tt path paths ->
            redirect output;
            signals
              (fun () ->
                match p with
                | Some p -> load p
                | None -> fail ~code:2 "signals needs --platform, or --raw")
              ~raw
              ~format:(if json then `Jsonl else format)
              ~changes ~cycles:(fc, tc) ~times:(ft, tt) path paths)
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
    model "commits" "Retired instructions with values and per-instruction cycles."
      Term.(
        const (fun features window limit profile format output p path ->
            redirect output;
            analyze
              (module Commits)
              () p ~format
              ~ctx:(ctx p ~features ~window ~limit ~profile ())
              Commits.text path)
        $ features $ window $ limit $ profile $ format $ output);
    model "stalls" Stalls.doc
      Term.(
        const (fun profile format output p path ->
            redirect output;
            analyze (module Stalls) () p ~format ~ctx:(ctx p ~profile ()) Stalls.text path)
        $ profile $ format $ output);
    model "memory" Memory.doc
      Term.(
        const (fun manifest window limit format output p path ->
            let region = regions p manifest in
            redirect output;
            analyze
              (module Memory)
              { region } p ~format ~ctx:(ctx p ~region ~window ~limit ()) Memory.text path)
        $ manifest $ window $ limit $ format $ output);
    model "axi" Axi.doc
      Term.(
        const (fun features manifest window limit profile format output p path ->
            let region = regions p manifest in
            redirect output;
            analyze
              (module Axi)
              { region } p ~format
              ~ctx:(ctx p ~features ~region ~window ~limit ~profile ())
              Axi.text path)
        $ features $ manifest $ window $ limit $ profile $ format $ output);
    model "dma" Dma.doc
      Term.(
        const (fun manifest beats format output p path ->
            let region = regions p manifest in
            redirect output;
            analyze (module Dma) { region } p ~format ~ctx:(ctx p ~region ()) (Dma.text ~beats) path)
        $ manifest
        $ Arg.(
            value & opt int 0
            & info [ "beats" ] ~docv:"N" ~doc:"Print the first $(docv) beats of each job.")
        $ format $ output);
    model "tiles" Tiles.doc
      Term.(
        const (fun limit format output p path ->
            redirect output;
            analyze (module Tiles) () p ~format ~ctx:(ctx p ~limit ()) Tiles.text path)
        $ limit $ format $ output);
    model "ops" Ops.doc
      Term.(
        const (fun features gap peak_window limit profile format output p path ->
            redirect output;
            analyze
              (module Ops)
              { gap; peak_window; features } p ~format ~ctx:(ctx p ~limit ~profile ()) Ops.text path)
        $ features
        $ Arg.(
            value & opt int Ops.Config.default.gap
            & info [ "gap" ] ~docv:"N"
                ~doc:"End a burst after $(docv) cycles with no vector arithmetic dispatched.")
        $ Arg.(
            value
            & opt int Ops.Config.default.peak_window
            & info [ "peak-window" ] ~docv:"N" ~doc:"Take the peak rate over $(docv) cycles.")
        $ limit $ profile $ format $ output);
    model "registers" Registers.doc
      Term.(
        const (fun at limit format output p path ->
            redirect output;
            analyze
              (module Registers)
              { at } p ~status:Registers.status ~format ~ctx:(ctx p ~limit ()) Registers.text path)
        $ at $ limit $ format $ output);
    model "vectors" Vectors.doc
      Term.(
        const (fun at limit format output p path ->
            redirect output;
            analyze
              (module Vectors)
              { at } p ~status:Vectors.status ~format ~ctx:(ctx p ~limit ()) Vectors.text path)
        $ at $ limit $ format $ output);
    model "traps" Traps.doc
      Term.(
        const (fun format output p path ->
            redirect output;
            analyze (module Traps) () p ~format ~ctx:(ctx p ()) Traps.text path)
        $ format $ output);
    cmd "run" "Run several analyses in one pass over a trace, each to its own text or JSONL sinks."
      Term.(
        const
          (fun
            p
            models
            sinks
            perfetto
            kanata
            report
            features
            manifest
            window
            limit
            profile
            at
            beats
            path
          ->
            run_models p ?perfetto ?kanata ?report
              {
                o_region = regions p manifest;
                o_features = features;
                o_window = window;
                o_limit = limit;
                o_profile = profile;
                o_at = at;
                o_beats = beats;
              }
              models sinks path)
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
                   standard output; repeatable.")
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
        $ features $ manifest $ window $ limit $ profile $ at $ beats $ traced);
    cmd "render" "Print a saved JSONL of an analysis as the text its command prints."
      Term.(
        const (fun platform features manifest window limit profile at beats file ->
            let p = load (Option.value platform ~default:(read_jsonl file).platform) in
            render p
              {
                o_region = regions p manifest;
                o_features = features;
                o_window = window;
                o_limit = limit;
                o_profile = profile;
                o_at = at;
                o_beats = beats;
              }
              file)
        $ saved_platform $ features $ manifest $ window $ limit $ profile $ at $ beats $ jsonl_file);
    cmd "profile" "Print the profile of a saved JSONL of commits, stalls or axi."
      Term.(
        const (fun platform features n file ->
            let p = load (Option.value platform ~default:(read_jsonl file).platform) in
            profile_of p
              {
                o_region = Region.none;
                o_features = features;
                o_window = Text.everything;
                o_limit = max_int;
                o_profile = n;
                o_at = None;
                o_beats = 0;
              }
              file)
        $ saved_platform $ features
        $ Arg.(
            value & opt int 10 & info [ "rows"; "n" ] ~docv:"N" ~doc:"The $(docv) heaviest rows.")
        $ jsonl_file);
    model "bench" "Time opening, decoding and sampling a trace."
      Term.(
        const (fun nodes p path -> Bench.run p ~select:!select ~nodes path)
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
    | exception Vcd.Parse_error msg ->
        flush stdout;
        prerr_endline ("coralview: " ^ msg);
        1
    | exception e ->
        flush stdout;
        prerr_endline ("coralview: internal error, uncaught exception:\n" ^ Printexc.to_string e);
        Cmd.Exit.internal_error)
