[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** A memory access: where, how many bytes, which direction, and the memory region named by the
    archive's manifest when one was given. *)

type t = { address : int; bytes : int; write : bool; region : string option }

val jsont : t Jsont.t
(** [region] is omitted when [None]. *)
