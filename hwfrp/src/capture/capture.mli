[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** The signals a set of graphs needs from a trace, as a plan: what a producer must record, and what a later run
    must find in the recording. A plan is built against a catalog (a trace whose events are not read), tagged
    with an {i origin} naming the graph, and checked against a selected trace before the first sample. *)

type entry = {
  aliases : Vcd_types.Reference.t list;  (** All of them, sorted. *)
  width : int;
  var_type : Vcd_ast.var_type;
  origins : string list;  (** Sorted; in the file. *)
  provenance : (string * string) list;  (** Model, purpose; sorted; not in the file. *)
}

type plan

val plan : origin:string -> Trace.t -> Frp.Net.t list -> plan
(** Every tracked signal of the trace, tagged with [origin], with the requirements of the nets as provenance.
    Raises [Invalid_argument] if the trace's events were pulled, or if [origin] is empty or has a comma or a
    whitespace character. *)

val union : plan list -> (plan, string list) result
(** By path, merging origins and provenance. The same path with a different width, variable type or alias group
    is an error, listed with its path. *)

val entries : plan -> entry list
(** Sorted by their first alias. *)

val origins : plan -> string list
(** Every origin of the plan, sorted. *)

val to_file : plan -> string
(** The line-oriented plan file, version 1. Raises [Invalid_argument] on a path component with a tab or a
    newline. *)

val of_file : string -> (plan, string) result
(** Strict inverse of {!to_file}; the error names the line. Provenance is empty. *)

val check : plan -> origins:string list -> Trace.t -> (unit, string list) result
(** After graph construction, before the first sample: the trace's tracked set equals the plan's signals with any
    of [origins], in paths, widths, variable types and alias groups. An origin absent from the plan is an error.
    Each planned group must resolve in the trace to one ID whose references equal the group. The errors are
    sorted. *)

module Verilator : sig
  val manifest :
    catalog:Trace.t ->
    producer:string ->
    format:Vcd_fst.format ->
    plan ->
    (string, string list) result
  (** The producer's selection manifest (version 1): one native name per alias of every planned signal, found by
      path in the catalog's scope tree. Only variables whose enclosing scopes are all [module] scopes are
      accepted, and only with no index or a bus range [[msb:lsb]]; a path with a component that has whitespace
      or a control character, a path missing from the catalog, an empty plan and an empty [producer] are errors,
      each listed with its path. *)
end
