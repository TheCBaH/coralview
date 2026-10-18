[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Profiles: events grouped by a key (usually a PC), counted and summed, heaviest first. *)

type 'k row = {
  key : 'k;
  count : int;
  weight : int;  (** The sum the rows are ordered by. *)
  total : int;  (** A second sum. *)
}

val by :
  ?buckets:int ->
  key:('e -> 'k option) ->
  ?weight:('e -> int) ->
  ?total:('e -> int) ->
  'e Seq.t ->
  'k row list
(** Events whose key is [None] are left out; [weight] and [total] default to 0 per event. Rows are by
    weight, descending, then by key, ascending. [buckets] (default 64) sizes the table. *)

val by_pc :
  ?buckets:int ->
  pc:('e -> int option) ->
  ?weight:('e -> int) ->
  ?total:('e -> int) ->
  'e Seq.t ->
  int row list

val pc_jsont : int row Jsont.t
(** [{"pc", "count", "weight", "total"}]. *)
