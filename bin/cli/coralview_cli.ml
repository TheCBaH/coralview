[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(* The command line: the groups of commands, and how an error ends the process. *)

open Coralview
open Cmdliner

let error_kind : Ovcd.Vcd.Error.error -> string = function
  | `Syntax _ -> "syntax"
  | `Incomplete _ -> "incomplete"
  | `Fst _ -> "fst"
  | `Io _ -> "io"
  | `Not_fst _ -> "not fst"
  | `Closed _ -> "closed"
  | `Superseded _ -> "superseded"
  | `Encoding _ -> "encoding"

let main () =
  Cli.exit
    (match
       Cmd.eval ~catch:false
         (Cmd.group
            (Cmd.info "coralview" ~exits:Terms.exits
               ~doc:"Observe the Coral NPU from the waveforms of its RTL simulators")
            (Trace_cmds.commands @ Code_cmds.commands @ Model_cmds.commands @ Run_cmds.commands))
     with
    | code -> code
    | exception Ovcd.Vcd.Error.E e ->
        flush stdout;
        prerr_endline
          (Printf.sprintf "coralview: trace read failed (%s): %s" (error_kind e)
             (Ovcd.Vcd.Error.to_string e));
        3
    | exception e ->
        flush stdout;
        prerr_endline ("coralview: internal error, uncaught exception:\n" ^ Printexc.to_string e);
        Cmd.Exit.internal_error)
