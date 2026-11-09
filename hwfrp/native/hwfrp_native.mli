[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** The native adapters of [hwfrp]: waveform files and FST, and the wall clock. The [hwfrp] library reads
    only VCD text and channels and depends on neither [unix] nor [ovcd.fst]. *)

val open_file : ?select:bool -> string -> Hwfrp.Trace.t
(** VCD or FST, by content. Raises [Vcd.Parse_error] or [Sys_error]. With [select] (the default), only
    the changes of the signals tracked by the time the events are read are decoded. *)

val open_file_result : ?select:bool -> string -> (Hwfrp.Trace.t, string) result
(** {!open_file} with its failures, [Vcd.Parse_error], [Sys_error] and an FST [Failure], as the message. *)

val open_string : ?select:bool -> string -> Hwfrp.Trace.t
(** VCD or FST bytes, by content. *)

val open_input : ?select:bool -> string -> Hwfrp.Trace.t
(** {!open_file}, or a VCD stream ({!Hwfrp_vcd.of_channel}) on standard input for the path ["-"]. *)

val wall_clock : unit -> float
(** Seconds, for [Hwfrp.Sched.run ~clock] and [Hwfrp.Run.start ~clock]. *)
