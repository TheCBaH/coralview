[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(* Commands on a trace or a platform: probe, tree, signals, platforms, check, plan, bench. *)

open Coralview
open Cli

let probe path =
  let { Ovcd.Vcd.header; simulation } = Hwfrp_native.parse_file path in
  let signals = Ovcd.Vcd.Resolver.fold (fun _ n -> n + 1) (Ovcd.Vcd.Resolver.make header) 0 in
  let times, changes, last =
    Seq.fold_left
      (fun (t, c, last) -> function
        | Ovcd.Ast.Timestamp ts -> (t + 1, c, Some ts)
        | Ovcd.Ast.Change _ -> (t, c + 1, last)
        | _ -> (t, c, last))
      (0, 0, None) simulation
  in
  Format.printf "signals %d@.timestamps %d@.changes %d@.last %a@." signals times changes
    (Format.pp_print_option Ovcd_types.Timestamp.pp)
    last

let tree ~depth ~vars path scope =
  Hwfrp_native.with_parse_file path @@ fun { Ovcd.Vcd.header; _ } ->
  let rec total (s : Ovcd.Ast.scope_node) =
    List.length s.vars + List.fold_left (fun n c -> n + total c) 0 s.children
  in
  let rec show indent d (s : Ovcd.Ast.scope_node) =
    Printf.printf "%s%s %d/%d\n" indent s.s_name (List.length s.vars) (total s);
    if d < depth then List.iter (show (indent ^ "  ") (d + 1)) s.children
  in
  let rec find nodes = function
    | [] -> nodes
    | n :: rest ->
        List.concat_map
          (fun (s : Ovcd.Ast.scope_node) -> if s.s_name = n then find s.children rest else [])
          nodes
  in
  let parts = if scope = "" then [] else String.split_on_char '/' scope in
  let parent = match List.rev parts with [] -> [] | _ :: up -> find header.scopes (List.rev up) in
  let here =
    match List.rev parts with
    | [] -> header.scopes
    | last :: _ -> List.filter (fun (s : Ovcd.Ast.scope_node) -> s.s_name = last) parent
  in
  if here = [] then fail ("no scope " ^ scope);
  List.iter
    (fun (s : Ovcd.Ast.scope_node) ->
      if vars then
        List.iter (fun (v : Ovcd.Ast.var_decl) -> Printf.printf "%s %d\n" v.ref v.size) s.vars
      else show "" 0 s)
    here

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
        Signals.raw
          ?path:(if path = "-" then None else Some path)
          tr paths
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
    | Error (`Io _ as e) -> fail ~code:2 (Ovcd.Vcd.Error.to_string e)
    | Error e -> raise (Ovcd.Vcd.Error.E e)
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
open Terms

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
    model "bench" "Time opening, decoding and sampling a trace."
      Term.(
        const (fun nodes env p path -> Bench.run p ~select:env.select ~nodes path)
        $ Arg.(
            value & opt int 300 & info [ "nodes" ] ~docv:"N" ~doc:"Nodes in the synthetic graph."));
  ]
