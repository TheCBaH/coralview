[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** The functions of an ELF, from its [.symtab] (the [FUNC] symbols), to name PCs and to find a function's
    address range. *)

type func = { name : string; address : int; size : int }
type t

val of_string : string -> (t, string) result
(** The ELF as bytes. A function with size 0 ends where the next one starts. Fails if the file is not an ELF
    or has no [.symtab]. *)

val load : string -> (t, string) result

val find : t -> string -> func list
(** The functions of that name, by address; several when it is a static name used in many files. *)

val lookup : t -> int -> (func * int) option
(** The function that contains a PC, and the offset in it. *)

val to_list : t -> func list
