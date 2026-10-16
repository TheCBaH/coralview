[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Values of named signals over a window: sampled once per cycle by the platform's clock and sample rule,
    or as the raw value changes of the trace. Paths are absolute, components separated by ['/'], so that
    scope names with dots ([VCoreMiniAxi.core]) stay whole. *)

type record = {
  cycle : int option;  (** [None] for raw changes. *)
  time : int64;  (** The trace timestamp. *)
  path : string;  (** As requested. *)
  width : int;
  value : Hwfrp.Logic.t;
}

exception Missing of string
(** A requested path that the trace does not have. *)

val model : string
val sample_rule_name : Hwfrp.Trace.sample_rule -> string

val require : Hwfrp.Trace.t -> string list -> unit
(** Raises {!Missing} for the first path the trace does not have. *)

val sampled :
  Platform.t ->
  Hwfrp.Trace.t ->
  string list ->
  from:int ->
  until:int ->
  changes:bool ->
  (record -> unit) ->
  unit
(** Each cycle from [from] to [until], in path order; with [changes], only values that differ from the
    previous cycle, but every value at the window's first cycle. Raises {!Missing}, and
    {!Hwfrp.Bind.Unbound} when the trace lacks the platform's clock. *)

val raw :
  Hwfrp.Trace.t ->
  string list ->
  from:int64 ->
  until:int64 ->
  changes:bool ->
  (record -> unit) ->
  unit
(** Each value change recorded at a timestamp from [from] to [until]; with [changes], only those that
    differ from the signal's previous value. Raises {!Missing}. *)

val to_string : Hwfrp.Logic.t -> string
(** [0x] and hex digits when every bit is known; otherwise [0b] and the bits, with [x] for unknown bits
    (and [h] for weak 1s). *)
