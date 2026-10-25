[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** A capture plan as JSON Lines, for [coralview plan --format jsonl]: a header record from {!Jsonl}, one
    [plan.signal] per planned signal with its provenance, then a [plan.summary]. *)

type signal = {
  width : int;
  var_type : string;
  origins : string list;
  aliases : string list list;  (** Each a path, one string per component. *)
  provenance : (string * string) list;  (** Model, purpose. *)
}

val of_entry : Hwfrp.Capture.entry -> signal
val signal_jsont : signal Jsont.t

type summary = { signals : int; selected : int; origins : string list }

val summary_jsont : summary Jsont.t
