[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(* The analysis commands and what is computed from them: one command a model, cost, summary, loops,
   compare. *)

open Coralview
open Cli

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

open Cmdliner
open Terms

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
  ]
