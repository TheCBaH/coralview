[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(* The command-line terms several commands share, and the wrappers that make a command of them. *)

open Coralview
open Cmdliner
open Cli

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

let exits =
  Cmd.Exit.info 1 ~doc:"a relation failed."
  :: Cmd.Exit.info 2 ~doc:"an invalid description, or a model the platform has no block for."
  :: Cmd.Exit.info 3
       ~doc:
         "the trace does not match the description (a signal is missing or wrong), or cannot be \
          read to its end."
  :: Cmd.Exit.defaults

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

let beats =
  Arg.(
    value & opt int 0 & info [ "beats" ] ~docv:"N" ~doc:"Print the first $(docv) beats of each job.")
