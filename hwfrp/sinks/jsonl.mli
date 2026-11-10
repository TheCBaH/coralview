[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** JSON Lines: an optional header object, then one object per record, each on a line. The key order
    of every object is the order it is given in, so an export can be compared byte for byte with the
    rendering of a rerun. *)

val to_string : ?header:Json.t -> Json.t Seq.t -> string
val output : out_channel -> ?header:Json.t -> Json.t Seq.t -> unit
