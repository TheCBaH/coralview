[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** The bindings [coralview check] reports, as records. *)

type binding = {
  model : string;
  root : string;
  path : string;  (** Relative to the root. *)
  width : string;  (** The rule the decoder sets. *)
  purpose : string option;
  status : string;  (** [bound], [missing], [width] or [type]. *)
  actual : int option;  (** The traced width, when there is a vector. *)
  detail : string option;  (** The variable type, for [type]. *)
}

val of_entry :
  string -> Vcd_types.Reference.t -> Hwfrp.Bind.requirement * Hwfrp.Bind.status -> binding

val ok : binding -> bool

val jsont : binding Jsont.t
(** [type] is [check.binding]. *)

type summary = { bound : int; failed : int }

val summary_jsont : summary Jsont.t
