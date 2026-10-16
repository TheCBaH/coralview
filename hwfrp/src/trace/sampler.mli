[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Turns the raw value changes of a trace into clock-domain samples. Only tracked signals are kept; the
    trace is frozen on creation. *)

type t

val create : Trace.t -> Trace.domain_spec array -> t

val next : t -> Trace.tick option
(** Advances to the next sample of any domain. Domains sampling at the same timestamp tick in this order:
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
