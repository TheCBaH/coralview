[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** An interval of cycles of one clock domain. *)

type t = {
  start : int;
  stop : int option;  (** Included; [None]: still open when the trace ended. *)
}

val length : t -> int option
(** Cycles, both ends included. *)
