[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Mutable sets of small non-negative integers with a fixed capacity. *)

type t

val create : int -> t
val capacity : t -> int
val add : t -> int -> unit
val mem : t -> int -> bool
val clear : t -> unit

val iter : (int -> unit) -> t -> unit
(** Ascending. *)

val is_empty : t -> bool
val elements : t -> int list
val remove : t -> int -> unit
