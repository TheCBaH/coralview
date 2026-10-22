[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** RV32 disassembly by Rivet, with Coral NPU's Zvt matrix instructions ({!Coral_zvt}). *)

type t

type instruction = {
  mnemonic : string;  (** Rivet's canonical mnemonic, e.g. [vfmacc.vf]. *)
  feature : string option;  (** The extension of a table-driven form, e.g. [v]. *)
}

val create : ?features:string -> unit -> (t, string) result
(** [features] is a Rivet feature spec such as ["none,+m,+zve32x,+xcoralzvt"]; Rivet's default set
    with [xcoralzvt] otherwise. *)

val decode : t -> int -> (string, string) result
(** The canonical spelling, or Rivet's diagnostic. *)

val disasm : t -> int -> string
(** The canonical spelling, or [.word 0x...] when Rivet has no form for the word under the features. *)

val instruction : t -> int -> (instruction, string) result
(** The word as Rivet decodes it under the features. *)

val assemble : t -> string -> (string, string) result
(** The little-endian bytes of the assembly text, assembled at address 0 under the features, or
    Rivet's diagnostic. The text is a whole source: one instruction per line. *)
