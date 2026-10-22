[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(* gen zvt.jsonl: the OCaml table of the instructions in the file devcontainer.coralnpu exports. *)

module Smap = Map.Make (String)

type instruction = {
  mnemonic : string;
  mask : string;
  match_ : string;
  fields : int list Smap.t;
  disasm : string;
  operands : string list;
}

let obj kind f = Jsont.Object.map ~kind f
let finish m = Jsont.Object.(finish (skip_unknown m))
let kind = obj "zvt record" Fun.id |> Jsont.Object.mem "record" Jsont.string |> finish

let provenance =
  obj "zvt provenance" Fun.id |> Jsont.Object.mem "schema_version" Jsont.int |> finish

let instruction =
  obj "zvt instruction" (fun mnemonic mask match_ fields disasm operands ->
      { mnemonic; mask; match_; fields; disasm; operands })
  |> Jsont.Object.mem "mnemonic" Jsont.string
  |> Jsont.Object.mem "mask" Jsont.string
  |> Jsont.Object.mem "match" Jsont.string
  |> Jsont.Object.mem "fields" (Jsont.Object.as_string_map Jsont.(list int))
  |> Jsont.Object.mem "disasm" Jsont.string
  |> Jsont.Object.mem "operands" Jsont.(list string)
  |> finish

let fail fmt =
  Printf.ksprintf
    (fun s ->
      prerr_endline ("zvt.jsonl: " ^ s);
      exit 1)
    fmt

let decode codec line =
  match Jsont_bytesrw.decode_string ~file:"zvt.jsonl" codec line with
  | Ok v -> v
  | Error e -> fail "%s" e

let read path = In_channel.with_open_bin path In_channel.input_all

let () =
  let lines =
    String.split_on_char '\n' (read Sys.argv.(1)) |> List.filter (fun l -> String.trim l <> "")
  in
  let instructions =
    match lines with
    | [] -> fail "empty"
    | first :: rest ->
        let record = decode kind first in
        if record <> "provenance" then fail "the first record is %s, not provenance" record;
        (match decode provenance first with 1 -> () | v -> fail "schema version %d, expected 1" v);
        List.map
          (fun line ->
            match decode kind line with
            | "instruction" -> decode instruction line
            | r -> fail "unexpected record %s" r)
          rest
  in
  print_string
    "type instruction = {\n\
    \  mnemonic : string;\n\
    \  mask : string;\n\
    \  match_ : string;\n\
    \  fields : (string * int list) list;\n\
    \  disasm : string;\n\
    \  operands : string list;\n\
     }\n\n\
     let instructions =\n\
    \  [\n";
  List.iter
    (fun i ->
      let list f l = "[" ^ String.concat "; " (List.map f l) ^ "]" in
      Printf.printf
        "    { mnemonic = %S; mask = %S; match_ = %S; fields = %s; disasm = %S; operands = %s };\n"
        i.mnemonic i.mask i.match_
        (list
           (fun (n, bits) -> Printf.sprintf "(%S, %s)" n (list string_of_int bits))
           (Smap.bindings i.fields))
        i.disasm
        (list (Printf.sprintf "%S") i.operands))
    instructions;
  print_string "  ]\n"
