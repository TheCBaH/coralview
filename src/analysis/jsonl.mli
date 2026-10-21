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

type 'e reader = {
  events : ('e, string) result Seq.t;
      (** The events in file order, each [Error] a line that is not a record of the analysis: malformed,
          a tag it does not have, a field of the wrong type. Reading goes on after an [Error]. Ephemeral. *)
  header : unit -> header option;  (** The first header, if one has been read. *)
  diags : unit -> Hwfrp.Diag.t list;  (** The diagnostics read so far. *)
  errors : unit -> string list;  (** The messages of the [Error]s so far, in order. *)
  finish : unit -> unit;
      (** Reads the rest of the lines, dropping the events: afterwards [header], [diags] and [errors] are
          complete and [events] has ended. Repeating it does nothing. *)
}

val reader : (module Output.OUTPUT with type Event.t = 'e) -> string Seq.t -> 'e reader
(** The events of a saved file, or of bare event lines: no header is required and the analysis need not
    be built. The header and the final [<name>.summary] line, the only lines skipped, and the diagnostics
    are kept apart from the events. Diagnostics follow the events in a saved file, so a reader that
    stops early has not seen them: call [finish]. *)

val channel_lines : in_channel -> string Seq.t
(** The lines of a channel, which stays the caller's to close; ephemeral. *)
