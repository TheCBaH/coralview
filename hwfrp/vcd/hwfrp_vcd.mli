[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** VCD text and streams as {!Hwfrp.Trace.t}, read with ovcd's VCD parser. *)

val of_string : ?select:bool -> string -> Hwfrp.Trace.t
(** VCD text. Raises [Vcd.Parse_error]. With [select] (the default), only the changes of the signals
    tracked by the time the events are read are decoded. *)

val of_channel : ?select:bool -> in_channel -> Hwfrp.Trace.t
(** A VCD stream, read as it arrives. Strict parsing (see [Vcd.parse_string]): a header that does not reach
    [$enddefinitions], and, when the events are consumed to the end, an open dump block or a last byte that is not
    a newline, raise [Vcd.Parse_error]. A cut at a record boundary is a valid prefix and is not detected. *)
