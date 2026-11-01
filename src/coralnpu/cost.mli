[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** The cost of the retired instructions by class and memory region: [commits] joined with [memory]. *)

type row = {
  cls : string;  (** {!Coral_isa.Iclass.name}, or ["unknown"]. *)
  region : string;
      (** Of the instance's first data request: the manifest's region, else ["tcm"] or ["ext"]; ["-"] for an
          instruction with no request. *)
  count : int;
  cycles : int;  (** Charged. *)
  d_to_r : int;  (** Dispatch to retire, summed. *)
}

val row_jsont : row Jsont.t
(** [{"type":"cost.row","class","region","count","cycles","d_to_r"}]. *)

val join :
  classify:(int -> string) ->
  window:Text.window ->
  Commits.commit list ->
  Memory.Event.access list ->
  row list
(** A request belongs to the youngest instance of its PC dispatched at or before it. Commits are those whose
    retire cycle and PC are in the window. Rows by cycles, descending. *)

val text : row list -> unit
