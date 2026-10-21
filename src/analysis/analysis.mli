[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** An analysis of a trace: typed events in stream order and a summary at the end, both with JSON
    codecs. An analysis is built in the net of a bound core; it is read by pulling its events as a
    sequence, or by subscribing to them, which lets several analyses share one pass. *)

module type S = sig
  val name : string
  (** The CLI command, and the prefix of its JSONL [type] tags. *)

  val doc : string

  val needs : string list
  (** The platform blocks it binds. *)

  module Config : sig
    type t

    val default : t
  end

  module Event : sig
    type t

    val jsont : t Jsont.t
    (** A case object: its [type] member is ["<name>.<record>"]. *)

    val cycle : t -> int
    (** For [--from-cycle] and [--to-cycle]. *)

    val pc : t -> int option
    (** For [--pc] and profiles. *)
  end

  module Summary : sig
    type t

    val jsont : t Jsont.t
    (** [type] is ["<name>.summary"]. *)
  end

  val build :
    Config.t -> 'c Core.t -> (Event.t list, 'c) Hwfrp.Ev.t * (Hwfrp.Sched.run_stats -> Summary.t)
  (** The events of each cycle, and the summary to read after the run. Raises {!Hwfrp.Bind.Unbound}
      and {!Core.No_block}. *)
end

type ('e, 's) t = (module S with type Event.t = 'e and type Summary.t = 's)

type ('e, 's) pulled = {
  events : 'e Seq.t;  (** Ephemeral: it advances the run. *)
  summary : unit -> 's;  (** Finishes the run first if the events are not exhausted. *)
  diags : unit -> Hwfrp.Diag.t list;  (** Recorded so far; all of them once finished. *)
  stats : unit -> Hwfrp.Sched.run_stats;
}

val pull :
  (module S with type Config.t = 'k and type Event.t = 'e and type Summary.t = 's) ->
  'k ->
  Platform.t ->
  Hwfrp.Trace.t ->
  ('e, 's) pulled
(** Binds the platform to the trace, builds the analysis alone and starts the run. Raises as {!S.build}. *)

val subscribe :
  (module S with type Config.t = 'k and type Event.t = 'e and type Summary.t = 's) ->
  'k ->
  'c Core.t ->
  ('e -> unit) ->
  Hwfrp.Sched.run_stats ->
  's
(** Builds the analysis in a core's net, calling the function on each event in stream order; the
    result reads the summary after the run. *)

val shared :
  'c Core.t ->
  string ->
  inj:('x -> 'c Core.dep) ->
  prj:('c Core.dep -> 'x option) ->
  (unit -> 'x) ->
  'x
(** [shared c name ~inj ~prj build] is the value an analysis named [name] was built to in [c]'s net, or
    [build ()], kept under [name] for the analyses built after it: an analysis that others depend on
    is built once per net. [inj] and [prj] are the analysis' own constructor of {!Core.dep}. *)

type ('e, 's) stream = {
  events : 'e Seq.t;  (** Ephemeral: it advances the run, and ends after [finish]. *)
  diags : unit -> Hwfrp.Diag.t list;  (** Recorded so far; all of them once finished. *)
  stats : unit -> Hwfrp.Sched.run_stats;  (** Finishes the run, as [finish] does. *)
  summary : unit -> 's;  (** Finishes the run, as [finish] does, then reads the model's summary. *)
  pending : unit -> int;  (** Events the model has produced and the sequence has not yet given. *)
  finish : unit -> unit;
      (** Runs to the end, dropping the events not yet pulled: they are not queued, so the memory held does
          not grow with the trace. Afterwards [diags] is complete and [events] has ended. Repeating it
          does nothing. *)
}
(** The events of one analysis, with what a caller needs to end the run: unlike {!pulled}, finishing does
    not keep the events it skips. The trace is read in the run's own pace; the FST file closes when the run
    reaches its end, and [Hwfrp.Trace] has no earlier close, so a stream abandoned before [finish] holds the
    file until it is collected. An exception of the model is raised by the sequence or by [finish]. *)

val stream :
  (module S with type Config.t = 'k and type Event.t = 'e and type Summary.t = 's) ->
  'k ->
  Platform.t ->
  Hwfrp.Trace.t ->
  ('e, 's) stream
(** Binds the platform to the trace and builds the analysis alone, as {!pull}. *)

val events_file :
  (module S with type Config.t = 'k and type Event.t = 'e and type Summary.t = 's) ->
  'k ->
  Platform.t ->
  string ->
  ('e, 's) stream
(** {!stream} on a trace file, FST or VCD by content. The platform is the caller's: a trace does not say
    which of its signals the analysis reads. *)
