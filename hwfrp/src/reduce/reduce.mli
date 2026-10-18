[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Reducers over sequences, for summaries and profiles. *)

module Stats : sig
  type t = { n : int; min : int; max : int; sum : int }

  val empty : t
  (** [n = 0]; [min] and [max] are [max_int] and [min_int]. *)

  val add : t -> int -> t
  val of_seq : int Seq.t -> t

  val mean : t -> float
  (** [nan] when empty. *)
end

module Histogram : sig
  type t
  (** Counts per integer key. *)

  val empty : t
  val add : ?count:int -> t -> int -> t
  val of_seq : int Seq.t -> t

  val to_list : t -> (int * int) list
  (** By key, ascending; keys with a zero count are absent. *)

  val total : t -> int
end

module Group : sig
  val by : ('a -> 'k) -> ('acc -> 'a -> 'acc) -> 'acc -> 'a Seq.t -> ('k * 'acc) list
  (** Folds the items of each key, the keys in the order of their first item. *)
end
