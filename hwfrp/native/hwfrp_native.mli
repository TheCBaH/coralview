[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** The native adapters of [hwfrp]: waveform files and FST, and the wall clock. The [hwfrp] library reads
    only VCD text and channels and depends on neither [unix] nor [ovcd.fst]. *)

val open_file : ?select:bool -> string -> Hwfrp.Trace.t
(** VCD or FST, by content. With [select] (the default), only the changes of the signals tracked by
    the time the events are read are decoded. A VCD file is parsed strictly, as a stream is
    ({!Hwfrp_vcd.of_channel}): reading its events to the end raises [Ovcd.Vcd.Error.E] with [`Incomplete]
    when its last byte is not a newline or a dump block is open.

    The file is closed when the events end or a pull raises. A reader that stops early, or never
    pulls, calls {!close}, or uses {!with_file}.

    Raises {!Ovcd.Vcd.Error.E}, and no other exception, when the file cannot be opened ([`Io]) or its
    header or hierarchy is damaged. Errors found while the events are read raise [Ovcd.Vcd.Error.E] from
    the trace's pulls. *)

val open_file_result : ?select:bool -> string -> (Hwfrp.Trace.t, Ovcd.Vcd.Error.error) result
(** {!open_file} returning the {!Ovcd.Vcd.Error.E} it raises at open time as [Error]; render it with
    [Ovcd.Vcd.Error.to_string]. Errors found later, while the events are read, still raise. *)

val with_file : ?select:bool -> string -> (Hwfrp.Trace.t -> 'a) -> 'a
(** {!open_file}, with the file closed when the function returns or raises. The trace, and its
    events, must not be used after. *)

val close : Hwfrp.Trace.t -> unit
(** Closes the file a trace of {!open_file} reads. Idempotent, and a no-op for any other trace. *)

val parse_file : ?select:(Ovcd_types.ID.t -> bool) -> string -> Ovcd.Vcd.parse_result
(** {!open_file}'s parse, for a reader of the raw events: VCD or FST, strict for VCD, closed at the end
    of the events. Raises as {!open_file} does. *)

val with_parse_file :
  ?select:(Ovcd_types.ID.t -> bool) -> string -> (Ovcd.Vcd.parse_result -> 'a) -> 'a
(** {!parse_file}, with the file closed when the function returns or raises. *)

val with_seek :
  ?select:(Ovcd_types.ID.t -> bool) ->
  string ->
  time:int64 ->
  (Ovcd.Vcd.Stateful.state -> Ovcd.Ast.event Seq.t -> 'a) ->
  'a option
(** For an FST file, [f state events] where [events] start at the whole timestep that begins the
    block holding [time] and [state] holds the selected IDs' values before them (see
    [Ovcd_fst.open_at]); the file is closed when [f] returns or raises. [None], without calling [f],
    for a VCD file and when [time] is not past the first block. *)

val open_string : ?select:bool -> string -> Hwfrp.Trace.t
(** VCD or FST bytes, by content. Raises {!Ovcd.Vcd.Error.E} as {!open_file} does. *)

val open_input : ?select:bool -> string -> Hwfrp.Trace.t
(** {!open_file}, or a VCD stream ({!Hwfrp_vcd.of_channel}) on standard input for the path ["-"]. Raises {!Ovcd.Vcd.Error.E}
    as {!open_file} does. *)

val with_input : ?select:bool -> string -> (Hwfrp.Trace.t -> 'a) -> 'a
(** {!open_input}, with the file closed when the function returns or raises; standard input stays
    open. *)

val wall_clock : unit -> float
(** Seconds, for [Hwfrp.Sched.run ~clock] and [Hwfrp.Run.start ~clock]. *)
