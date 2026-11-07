[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** A sidecar of labels for addresses, written by a producer that knows where its code came from, joined
    into [disasm] and [commits] text.

    One entry a line, [LOCATION LABEL]: the label is the rest of the line. Blank lines and lines starting
    with [#] are skipped. A location is

    - [NAME]: the whole function [NAME] of the ELF;
    - [NAME+OFF] or [NAME+OFF-OFF]: the byte at that offset, or the offsets from the first up to but not
      including the second;
    - [0xADDR] or [0xADDR-0xADDR], or eight hex digits: the same by absolute address.

    Offsets are decimal or [0x] hexadecimal. Several entries can cover one address; all their labels apply. *)

type t

val parse : functions:(string -> (int * int) list) -> string -> (t, string) result
(** [functions name] gives the [(address, size)] of the functions of that name. An entry naming a function
    not there, or a malformed location, is an error with its line number. *)

val load : functions:(string -> (int * int) list) -> string -> (t, string) result

val labels : t -> int -> string list
(** The labels that cover an address, in file order. *)
