[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Turns the raw value changes of a trace into clock-domain samples. Only tracked signals are kept; the
    trace is frozen on creation. *)

type t

val create : Trace.t -> Trace.domain_spec array -> t

type poll =
  | Tick of Trace.tick
  | Starved  (** The source has no more events for now; a sample may need later ones. *)
  | Ended

val poll : t -> poll
(** Advances to the next sample of any domain, or says why there is none. A sample is final only when
    the next timestamp or the end of the source has been seen, so a source cut mid-timestamp is
    [Starved] until it continues: the samples are the same however the events are batched. Polling a
    [Starved] sampler again after the source has more events resumes where it stopped. Domains sampling
    at the same timestamp tick in this order: [Before_rising] domains, then the changes are applied,
    then the [After_*] domains, each group in domain order. *)

val next : t -> Trace.tick option
(** {!poll} for a source that is never starved: [None] at its end. Raises [Invalid_argument] on
    [Starved]. Advances to the next sample of any domain. Domains sampling at the same timestamp tick in this order:
    [Before_rising] domains, then the changes are applied, then the [After_*] domains, each group in domain
    order. *)

val value : t -> Trace.slot -> Vcd_types.Value.t
(** The current sampled value; X before the first change. *)

val logic : t -> Trace.slot -> Logic.t
(** {!value} as a 4-state vector, cached until the slot changes; all unknown when it is not a bit vector. *)

val changed : t -> Bitset.t
(** Slots whose value differs from the previous sample of the domain being ticked. *)

type stats = { events : int; changes_seen : int; changes_tracked : int; timestamps : int }

val stats : t -> stats
