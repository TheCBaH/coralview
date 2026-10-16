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

val open_file : string -> t
(** VCD or FST, by content. Raises [Vcd.Parse_error] or [Sys_error]. *)

val of_string : string -> t
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
(** The raw value changes. Raises [Invalid_argument] when called twice. *)

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
