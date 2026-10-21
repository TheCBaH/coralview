[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** The processed events of an analysis, as JSON Lines records: what a consumer needs to read or write
    them, without the model that computes them. Every {!Analysis.S} satisfies it. *)

module type OUTPUT = sig
  val name : string

  module Event : sig
    type t

    val jsont : t Jsont.t
  end
end

val decode_event : (module OUTPUT with type Event.t = 'e) -> string -> ('e, string) result
(** One record, a JSON object without its newline. Malformed JSON, a wrong tag or a field of the wrong type
    is an [Error]; it does not raise. *)

val decode_events :
  (module OUTPUT with type Event.t = 'e) -> string Seq.t -> ('e, string) result Seq.t
(** [Seq.map (decode_event o)]: lazy, and an [Error] does not end the sequence. *)

val encode_event : (module OUTPUT with type Event.t = 'e) -> 'e -> string
(** Minified, without the newline. *)
