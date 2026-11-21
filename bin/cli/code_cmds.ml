[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(* Commands on instruction words and ELF code: decode, disasm. *)

open Coralview
open Cli

let decode features words =
  let d = decoder features in
  List.iter
    (fun w ->
      match Coral_isa.Rivet_decode.decode d (int_of_string ("0x" ^ w)) with
      | Ok s -> Printf.printf "%s  %s\n" w s
      | Error e -> Printf.printf "%s  error: %s\n" w e)
    words

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

open Cmdliner
open Terms

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

let commands =
  [
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
  ]
