[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** A waveform opened for sampling, and the signals tracked in it. *)

type slot = private int
(** Dense index of a tracked signal. *)

type signal = {
  slot : slot;
  id : Ovcd_types.ID.t;
  path : Ovcd_types.Reference.t;  (** The least of the aliases. *)
  aliases : Ovcd.Vcd.Ref_set.t;
  width : int;
  var_type : Ovcd.Ast.var_type;
}

type t

type format = [ `Vcd | `Fst ]
(** What the events were read from. Informational: the core parses nothing; see the [hwfrp.vcd] and
    [hwfrp.native] libraries. *)

type pull =
  | Event of Ovcd.Ast.event
  | Starved  (** No event now; more may come. *)
  | Ended  (** No event ever again. *)

val of_pull : format:format -> Ovcd.Ast.header -> (unit -> pull) -> t
(** A trace whose events a producer hands over one at a time, and may not have yet. *)

val of_parse :
  ?select:bool -> format:format -> ((Ovcd_types.ID.t -> bool) option -> Ovcd.Vcd.parse_result) -> t
(** A trace from a parser that takes ovcd's [select] predicate: the adapter for any other source.
    With [select] (the default), only the changes of the signals tracked by the time {!events} is
    called are read. *)

val on_close : t -> (unit -> unit) -> unit
(** Registers what {!close} does for the resource the events are read from. *)

val close : t -> unit
(** Releases what the trace's source holds open, most recent registration first. Idempotent. Events
    pulled afterwards are an error of the source. *)

val format : t -> format
val header : t -> Ovcd.Ast.header
val resolver : t -> Ovcd.Vcd.Resolver.t
val lookup : t -> Ovcd_types.Reference.t -> Ovcd.Vcd.Resolver.entry option

val unbound : path:Ovcd_types.Reference.t -> width:int -> signal
(** A stand-in for a signal the trace does not have, with an invalid slot. Only a net that is never
    run may hold one: see [Frp.Net.poison]. *)

val track : t -> Ovcd.Vcd.Resolver.entry -> signal
(** Idempotent. Raises [Invalid_argument] once the trace is frozen. *)

val track_path : t -> string -> signal option
(** [lookup] and [track] of a dotted path. *)

val tracked : t -> signal array
(** In slot order. *)

val freeze : t -> unit

val events : t -> Ovcd.Ast.event Seq.t
(** The raw value changes, of the tracked signals only unless opened with [~select:false]. Freezes
    the trace. Raises [Invalid_argument] when called twice, and when the sequence is traversed to
    a {!Starved} source. *)

val pull : t -> unit -> pull
(** {!events} as a function, which tells a source that has no event yet from one that has ended. *)

val events_pulled : t -> bool
(** Whether {!events} has been called: the trace is no longer a declaration-only binding environment. *)

type sample_rule =
  | After_falling  (** State after the changes of the timestamp at which the clock went 1 to 0. *)
  | Before_rising  (** State before the changes of the timestamp at which the clock went 0 to 1. *)
  | After_rising  (** State after the changes of the rising-edge timestamp. *)

type reset = { signal : slot; active : bool }
(** A reset signal and the level at which it holds the design in reset. *)

type domain_spec = {
  clock : slot;
  rule : sample_rule;
  enable : slot option;
  reset : reset option;
      (** The samples taken unless the signal is known to be at its inactive level are [in_reset]: an
          unknown level, such as before the first change, is a design not yet out of reset. *)
}

type tick = {
  domain : int;  (** Index in the domain list. *)
  index : int;  (** 0-based cycle number in that domain. *)
  time : Ovcd_types.Timestamp.t;
  enabled : bool;
  in_reset : bool;
      (** The reset of the domain's spec is asserted at this sample; false without one. *)
}

val find : t -> string list -> signal option
(** [lookup] and [track] of a path given as components, for scope names that contain dots. *)

val paths_ending : t -> string -> Ovcd_types.Reference.t list
(** Every signal path whose last component is the given name, shortest first. *)

val var_type : t -> Ovcd.Vcd.Resolver.entry -> Ovcd.Ast.var_type

val scope_vars : t -> Ovcd_types.Reference.t -> (string * int) list
(** The names and widths of the variables declared directly in a scope, in declaration order. *)
