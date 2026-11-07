[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** The code of an RV32 little-endian ELF, disassembled by Rivet (Coral's Zvt included) and labelled by
    its symbols. Words are 4 bytes: an ELF that marks compressed instructions is refused. *)

type line = {
  address : int;
  word : int;
  text : string;  (** Rivet's spelling, or [.word 0x...] for a word it has no form for, or data. *)
  instruction : Coral_isa.Rivet_decode.instruction option;  (** [None] for [.word]. *)
  symbol : string option;  (** The last label at or before the address in its section. *)
  target : string option;
      (** [<name>] or [<name+0xN>] for the destination of a [jal] or a branch inside an executable section. *)
}

type item = Label of string | Line of line

type scope = {
  sections : string list;  (** Executable sections to list; all of them when empty. *)
  functions : string list;
      (** Only the extent of these [FUNC] symbols; no restriction when empty. *)
  range : (int * int) option;  (** Only addresses in [\[lo, hi)]. *)
}

val everything : scope

val listing : Coral_isa.Rivet_decode.t -> scope -> string -> (item list, string) result
(** The ELF as bytes. Sections in address order, a {!Label} before the first word of each address that has
    symbols ([FUNC] first, then untyped labels; mapping symbols and [.L] names are not labels). A word
    Rivet has no form for is a [.word], whatever the mapping symbols say: the toolchain marks Coral's Zvt
    words, which it can only write as [.word], as data. A stripped ELF lists without labels, but
    cannot be restricted to functions. A word is listed if its address is in every restriction. *)

val pp_text : Format.formatter -> item list -> unit
(** One instruction per line: address, raw word, spelling, then the target; a [name:] line at each label. *)

val line_jsont : line Jsont.t
(** [{"address","word","text","mnemonic","class","symbol","target"}]: the last four are omitted when absent. *)

val lines : item list -> line list
