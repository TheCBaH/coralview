[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** RV32 disassembly by Rivet, with Coral NPU's Zvt matrix instructions ({!Coral_zvt}). *)

type t

val create : ?features:string -> unit -> (t, string) result
(** [features] is a Rivet feature spec such as ["none,+m,+zve32x,+xcoralzvt"]; Rivet's default set
    with [xcoralzvt] otherwise. *)

val decode : t -> int -> (string, string) result
(** The canonical spelling, or Rivet's diagnostic. *)

val disasm : t -> int -> string
(** The canonical spelling, or [.word 0x...] when Rivet has no form for the word under the features. *)
