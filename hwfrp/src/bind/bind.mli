[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Binding model inputs to trace signals by path, recording what each model requires so that a missing or
    mismatched signal fails {!Frp.Sched.compile} and can be listed by [check]. *)

type need = Required | Optional
type width_rule = Exact of int | At_least of int | Up_to of int | Any_width

type requirement = {
  model : string;
  root : Vcd_types.Reference.t;
  path : Vcd_types.Reference.t;  (** Absolute, after the root and the overrides. *)
  width : width_rule;
  need : need;
  purpose : string;
}

type status =
  | Bound of Trace.signal
  | Missing
  | Width_mismatch of { expected : width_rule; actual : int }
  | Not_a_vector of Vcd_ast.var_type

type report = {
  model : string;
  root : Vcd_types.Reference.t;
  entries : (requirement * status) list;
}

val clock :
  Frp.Net.t ->
  Trace.t ->
  model:string ->
  ?purpose:string ->
  name:string ->
  ?enable:Vcd_types.Reference.t ->
  Trace.sample_rule ->
  Vcd_types.Reference.t ->
  Frp.Clock.any option
(** A clock domain sampled on a 1-bit signal; [None], with the failure recorded, when it is not bound. *)

type 'c scope

val root :
  Frp.Net.t ->
  Trace.t ->
  'c Frp.Clock.t ->
  model:string ->
  ?overrides:(string * Vcd_types.Reference.t) list ->
  Vcd_types.Reference.t ->
  'c scope
(** [overrides] maps a path relative to the root, components joined by ['.'], to the absolute path to bind
    instead. *)

val sub : 'c scope -> string -> 'c scope
(** One scope component, taken literally. *)

val path : 'c scope -> Vcd_types.Reference.t

val vars : 'c scope -> (string * int) list
(** The variables declared directly in the scope, with their widths. *)

val find_roots : Trace.t -> Filter_ast.pattern -> Vcd_types.Reference.t list
(** The scopes whose paths match, outermost first. *)

type 'a decoder = {
  dname : string;
  dwidth : width_rule;
  decode : Logic.t -> ('a, Logic.t) result;  (** [Error] when bits that matter are X or Z. *)
  default : int -> 'a;
      (** The value at a width before the first sample, in place of an [Error] (reported as a
          [bind.unknown-bits] diagnostic) and for unbound signals. *)
}

val bool : bool decoder
val uint : int decoder
val bits : Bits.t decoder
val logic : Logic.t decoder
val field : lo:int -> width:int -> int decoder

val signal : ?need:need -> ?purpose:string -> 'c scope -> string -> 'a decoder -> ('a, 'c) Frp.Sig.t
(** A constant [default] when not bound; a [Required] one also fails compilation. *)

val optional : ?purpose:string -> 'c scope -> string -> 'a decoder -> ('a option, 'c) Frp.Sig.t
(** Constant [None] when not bound. *)

val requirements : Frp.Net.t -> requirement list
(** In binding order. *)

val check : Trace.t -> requirement list -> report list
(** The requirements resolved against a trace, grouped by model and root in first-seen order. *)

val failed : requirement * status -> bool
(** A [Required] requirement that is not bound. *)

val pp_width_rule : Format.formatter -> width_rule -> unit
val pp_report : Format.formatter -> report -> unit
