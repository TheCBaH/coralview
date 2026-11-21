[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** One run of one net for a command that needs several analyses of a trace, or the retirements to find a
    window in, and keeps what they produce: the trace is read once. *)

type 'r builder = { build : 'c. 'c Core.t -> Hwfrp.Sched.run_stats -> 'r }
(** Builds in a core's net what it will read after the run, and returns the reader. *)

val run :
  ?gate:(Hwfrp.Trace.t -> model:string -> unit) ->
  Platform.t ->
  Hwfrp.Trace.t ->
  model:string ->
  'r builder ->
  'r * Hwfrp.Diag.t list
(** Binds the platform, calls [build], runs the trace to its end after [gate] (see {!Core.start}), and
    reads. The diagnostics are those of the whole net. Raises as {!Analysis.S.build}. *)

val collect :
  (module Analysis.S with type Config.t = 'k and type Event.t = 'e and type Summary.t = 's) ->
  'k ->
  'c Core.t ->
  Hwfrp.Sched.run_stats ->
  'e list * 's
(** Builds an analysis in the net, keeping its events in stream order: the same as {!Analysis.pull} gives
    when it is alone. What it binds is blamed on its own name. *)

val commits : 'c Core.t -> Hwfrp.Sched.run_stats -> Commits.commit list
(** The retirements, in order. *)
