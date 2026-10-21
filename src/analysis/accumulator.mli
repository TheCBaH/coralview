[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** Totals of an analysis' events, kept as they arrive. An accumulator knows only what the events carry:
    what the model also tracks (the cycles of the trace, what is still in flight) is not in a snapshot
    unless the events say it. *)

module type ACCUMULATOR = sig
  type event
  type t
  type snapshot

  val create : unit -> t

  val add : t -> event -> unit
  (** Updates the accumulator alone. *)

  val snapshot : t -> snapshot
  (** The totals of the events added so far. It changes nothing, can be taken between any two [add]s and
      does not change when more events are added. *)
end

val tap : (module ACCUMULATOR with type t = 'a and type event = 'e) -> 'a -> 'e Seq.t -> 'e Seq.t
(** The same events, each added to the accumulator as it is pulled. Single-use: traversing the result a
    second time raises {!Seq.Forced_twice}, which would add the events twice. *)
