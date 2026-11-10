[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** Text with one record per line, as the files a run exports: the same records always give the same
    bytes. *)

val to_string : string Seq.t -> string
(** Each line is followed by a newline. A line must not contain one. *)

val output : out_channel -> string Seq.t -> unit
