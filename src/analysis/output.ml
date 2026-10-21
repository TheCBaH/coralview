[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

module type OUTPUT = sig
  val name : string

  module Event : sig
    type t

    val jsont : t Jsont.t
  end
end

let decode_event (type e) (module O : OUTPUT with type Event.t = e) line =
  Codec.of_line O.Event.jsont line

let decode_events o lines = Seq.map (decode_event o) lines

let encode_event (type e) (module O : OUTPUT with type Event.t = e) event =
  Codec.to_line O.Event.jsont event
