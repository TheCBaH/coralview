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
  func : string option;  (** The last [FUNC] symbol at or before the address in its section. *)
  target : string option;
      (** [<name>] or [<name+0xN>] for the destination of a [jal] or a branch inside an executable section. *)
  vconfig : string option;  (** From {!with_vconfig}. *)
  annotation : string option;  (** From {!with_annotations}. *)
}

type item =
  | Label of string
  | Line of line
  | Padding of { address : int; words : int }  (** A run of zero words, from {!collapse_padding}. *)

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

val collapse_padding : item list -> item list
(** Runs of two or more consecutive all-zero words become one {!Padding}. *)

val padding_jsont : (int * int) Jsont.t
(** [{"padding_words":n,"address":a}] for a {!Padding}; with {!collapse_padding} in the JSONL. *)

val summary : item list -> (string * (string * int) list) list
(** Instructions per class by function, in listing order; the classes are those of [class] in the JSONL, and
    [data] for a word with no form. [?] is code outside any [FUNC] symbol. *)

val pp_summary : Format.formatter -> (string * (string * int) list) list -> unit
(** One line a function: [name: N instructions, class n, …]. *)

val with_vconfig : item list -> item list
(** Sets [vconfig] on each vector instruction to the configuration the vsetvli or vsetivli words reaching it
    agree on, like [e32,m4,ta,ma avl 16] ([avl x10] for a register, [max] for [x0], no avl where paths
    disagree), or [vtype unknown] where none does: no vset before it in the function, a call or a vsetvl in
    between, or two vtypes meeting. The analysis follows branches and jumps inside the FUNC symbol. *)

val with_annotations : (int -> string list) -> item list -> item list
(** Sets [annotation] on each line the function gives labels for, joined with ["; "]; printed as
    [  ; label] after the other comments. *)
