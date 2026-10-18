[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** An analysis as JSON Lines: a header record, then the events and diagnostics, then one summary
    record. Every line is an object with a [type] member. *)

type header = { schema_version : int; model : string; platform : string; trace : string }

val schema_version : int
val header : model:string -> platform:string -> trace:string -> header

val header_jsont : header Jsont.t
(** [{"type":"coralview","schema_version":1,"model":…,"platform":…,"trace":…}]. *)

val write :
  out_channel ->
  header ->
  ('e, 's) Analysis.t ->
  'e Seq.t ->
  diags:(unit -> Hwfrp.Diag.t list) ->
  (unit -> 's) ->
  unit
(** Writes the lines in order. The diagnostics and the summary are read once the events are
    exhausted. *)

type ('e, 's) line = Header of header | Event of 'e | Diag of Hwfrp.Diag.t | Summary of 's

val line : ('e, 's) Analysis.t -> string -> (('e, 's) line, string) result
(** Decodes one line by its [type]. *)

val read : ('e, 's) Analysis.t -> in_channel -> (('e, 's) line, string) result Seq.t
(** The lines of a file, decoded; ephemeral. *)
