[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** A dynamic instance of an instruction: its PC and word, and the cycles it went through the core's
    stages, as far as the debug ports and the analysis know them. *)

type t = {
  pc : int;
  word : int option;
  dispatched : int option;
  issued : int option;  (** Left its unit's queue, where the analysis follows one. *)
  retired : int option;
}

val jsont : t Jsont.t
