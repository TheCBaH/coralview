[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** RV32 disassembly by Rivet. The only module that uses Rivet's API. *)

type t

val create : ?features:string -> unit -> (t, string) result
(** [features] is a Rivet feature spec such as ["+v"]; Rivet's default set otherwise. *)

val decode : t -> int -> (string, string) result
(** The canonical spelling, or Rivet's diagnostic. *)

val disasm : t -> int -> string
(** The canonical spelling, or [.word 0x...] when Rivet has no form for the word under the features. *)
