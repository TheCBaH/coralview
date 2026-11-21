[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** A JSON value and its writer. Compact, with the object keys in the order given, so the same value
    always renders to the same bytes: what a replay that compares output with a file needs. No reader. *)

type t =
  | Int of int
  | Float of float
      (** The shortest of 15, 16 or 17 significant digits that reads back to the same float, with
          [.0] added when it would otherwise look like an integer; [-0.] is [-0.0]. NaN and the
          infinities have no JSON form and are written as [null]. *)
  | Str of string
  | Bool of bool
  | Null
  | List of t list
  | Obj of (string * t) list  (** Written in list order. Duplicate keys are not checked. *)

val to_string : t -> string
(** No whitespace. In strings, ['"'], ['\\'], newline, return and tab are escaped by name and other
    the other control characters and DEL as [\u00XX] with capital hex digits, as jsont does; the bytes above 0x7f are written as they are, so the output is
    UTF-8 only if the strings are. *)
