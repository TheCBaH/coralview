[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

type t =
  | Int of int
  | Str of string
  | Bool of bool
  | Null
  | List of t list
  | Obj of (string * t) list

let add_string b s =
  Buffer.add_char b '"';
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c when Char.code c < 0x20 || c = '\127' ->
          Buffer.add_string b (Printf.sprintf "\\u%04X" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"'

let rec add b = function
  | Int n -> Buffer.add_string b (string_of_int n)
  | Str s -> add_string b s
  | Bool x -> Buffer.add_string b (if x then "true" else "false")
  | Null -> Buffer.add_string b "null"
  | List l ->
      Buffer.add_char b '[';
      List.iteri
        (fun i x ->
          if i > 0 then Buffer.add_char b ',';
          add b x)
        l;
      Buffer.add_char b ']'
  | Obj l ->
      Buffer.add_char b '{';
      List.iteri
        (fun i (k, x) ->
          if i > 0 then Buffer.add_char b ',';
          add_string b k;
          Buffer.add_char b ':';
          add b x)
        l;
      Buffer.add_char b '}'

let to_string j =
  let b = Buffer.create 128 in
  add b j;
  Buffer.contents b
