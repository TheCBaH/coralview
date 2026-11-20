[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** The functions of an ELF, from its [.symtab], to name PCs and to find a function's address range: the
    [FUNC] symbols, and the untyped ([NOTYPE]) ones defined in an executable section, which is what an
    assembly entry point without [.type] is. Mapping symbols ([$x], [$d]) and [.L] names are left out. *)

type func = { name : string; address : int; size : int }
type t

val of_string : string -> (t, string) result
(** The ELF as bytes. A symbol with size 0 ends where the next one starts: a [FUNC] at the next [FUNC], an
    untyped one at the next symbol of either kind. Fails if the file is not an ELF or has no [.symtab]. *)

val load : string -> (t, string) result

val find : t -> string -> func list
(** The functions of that name, by address; several when it is a static name used in many files. *)

val lookup : t -> int -> (func * int) option
(** The function that contains a PC, and the offset in it. Where several do, the latest [FUNC] to start,
    else the latest untyped symbol: a function is not hidden by a smaller one inside it. *)

val to_list : t -> func list
