[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** JSON codecs shared by the analyses: the [type] tag every JSONL line carries, the hwfrp records, and
    line encoding. Integers are JSON numbers. *)

val tag : string -> unit Jsont.t
(** The string [name], and nothing else. *)

val record : string -> 'dec -> ('o, 'dec) Jsont.Object.map
(** An object whose first member is [{"type": name}]. *)

val case : string -> ('c -> 'a) -> 'c Jsont.t -> ('a, 'c, string) Jsont.Object.Case.map
(** A case of {!cases}: the object of a variant with [{"type": name}]. *)

val cases :
  string ->
  ('a -> ('a, string) Jsont.Object.Case.value) ->
  ('a, string) Jsont.Object.Case.t list ->
  'a Jsont.t
(** A variant as objects told apart by their [type] member. *)

val opt :
  ('a -> 'b option) ->
  string ->
  'b Jsont.t ->
  ('a, 'b option -> 'c) Jsont.Object.map ->
  ('a, 'c) Jsont.Object.map
(** An optional member, omitted when [None]. *)

val span : Hwfrp.Span.t Jsont.t
(** [{"start", "stop"}]; no [stop] when open. *)

val transaction : Hwfrp.Transaction.t Jsont.t
val diag : Hwfrp.Diag.t Jsont.t

val stats : Hwfrp.Reduce.Stats.t Jsont.t
(** [{"n", "min", "max", "sum"}]; no [min] and [max] when empty. *)

val bits : Hwfrp.Bits.t Jsont.t
(** Hex digits, most significant first, as {!Hwfrp.Bits.to_hex}; decodes to a width of 4 bits per
    digit. *)

val to_line : 'a Jsont.t -> 'a -> string
(** Minified, without the newline. Raises [Invalid_argument] if the value does not encode. *)

val of_line : 'a Jsont.t -> string -> ('a, string) result
(** A decoder that raises [Invalid_argument] or [Failure] on a value of the right JSON type is an [Error]. *)
