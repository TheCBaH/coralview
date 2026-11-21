[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(* Several analyses in one run, and saved JSONL turned back into text: run, render, profile. *)

open Coralview
open Cli

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

open Cmdliner
open Terms

let saved_platform =
  Arg.(
    value
    & opt (some string) None
    & info [ "platform"; "p" ] ~docv:"P"
        ~doc:"The platform, when the file's is not built in: as for the analyses.")

let jsonl_file = Arg.(required & pos 0 (some file) None & info [] ~docv:"FILE" ~doc:"A JSONL file.")

let commands =
  [
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
  ]
