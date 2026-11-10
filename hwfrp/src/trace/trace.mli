[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** A waveform opened for sampling, and the signals tracked in it. *)

type slot = private int
(** Dense index of a tracked signal. *)

type signal = {
  slot : slot;
  id : Vcd_types.ID.t;
  path : Vcd_types.Reference.t;  (** The least of the aliases. *)
  aliases : Vcd.Ref_set.t;
  width : int;
  var_type : Vcd_ast.var_type;
}

type t

type format = [ `Vcd | `Fst ]
(** What the events were read from. Informational: the core parses nothing; see the [hwfrp.vcd] and
    [hwfrp.native] libraries. *)

type pull =
  | Event of Vcd_ast.event
  | Starved  (** No event now; more may come. *)
  | Ended  (** No event ever again. *)

val of_pull : format:format -> Vcd_ast.header -> (unit -> pull) -> t
(** A trace whose events a producer hands over one at a time, and may not have yet. *)

val of_parse :
  ?select:bool -> format:format -> ((Vcd_types.ID.t -> bool) option -> Vcd.parse_result) -> t
(** A trace from a parser that takes ovcd's [select] predicate: the adapter for any other source.
    With [select] (the default), only the changes of the signals tracked by the time {!events} is
    called are read. *)

val format : t -> format
val header : t -> Vcd_ast.header
val resolver : t -> Vcd.Resolver.t
val lookup : t -> Vcd_types.Reference.t -> Vcd.Resolver.entry option

val unbound : path:Vcd_types.Reference.t -> width:int -> signal
(** A stand-in for a signal the trace does not have, with an invalid slot. Only a net that is never
    run may hold one: see [Frp.Net.poison]. *)

val track : t -> Vcd.Resolver.entry -> signal
(** Idempotent. Raises [Invalid_argument] once the trace is frozen. *)

val track_path : t -> string -> signal option
(** [lookup] and [track] of a dotted path. *)

val tracked : t -> signal array
(** In slot order. *)

val freeze : t -> unit

val events : t -> Vcd_ast.event Seq.t
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

type domain_spec = { clock : slot; rule : sample_rule; enable : slot option }

type tick = {
  domain : int;  (** Index in the domain list. *)
  index : int;  (** 0-based cycle number in that domain. *)
  time : Vcd_types.Timestamp.t;
  enabled : bool;
}

val find : t -> string list -> signal option
(** [lookup] and [track] of a path given as components, for scope names that contain dots. *)

val paths_ending : t -> string -> Vcd_types.Reference.t list
(** Every signal path whose last component is the given name, shortest first. *)

val var_type : t -> Vcd.Resolver.entry -> Vcd_ast.var_type

val scope_vars : t -> Vcd_types.Reference.t -> (string * int) list
(** The names and widths of the variables declared directly in a scope, in declaration order. *)
