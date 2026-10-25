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

val open_file : ?select:bool -> string -> t
(** VCD or FST, by content. Raises [Vcd.Parse_error] or [Sys_error]. With [select] (the default),
    only the changes of the signals tracked by the time {!events} is called are read. *)

val of_string : ?select:bool -> string -> t

val of_channel : ?select:bool -> in_channel -> t
(** A VCD stream, read as it arrives. Strict parsing (see [Vcd.parse_string]): a header that does not reach
    [$enddefinitions], and, when the events are consumed to the end, an open dump block or a last byte that is not
    a newline, raise [Vcd.Parse_error]. A cut at a record boundary is a valid prefix and is not detected. FST is not
    accepted. *)

val open_input : ?select:bool -> string -> t
(** {!open_file}, or {!of_channel} on standard input for the path ["-"]. *)
val format : t -> Vcd_fst.format
val header : t -> Vcd_ast.header
val resolver : t -> Vcd.Resolver.t
val lookup : t -> Vcd_types.Reference.t -> Vcd.Resolver.entry option

val track : t -> Vcd.Resolver.entry -> signal
(** Idempotent. Raises [Invalid_argument] once the trace is frozen. *)

val track_path : t -> string -> signal option
(** [lookup] and [track] of a dotted path. *)

val tracked : t -> signal array
(** In slot order. *)

val freeze : t -> unit

val events : t -> Vcd_ast.event Seq.t
(** The raw value changes, of the tracked signals only unless opened with [~select:false]. Freezes
    the trace. Raises [Invalid_argument] when called twice. *)

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
