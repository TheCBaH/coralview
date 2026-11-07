[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** Two runs of one kernel side by side: the summaries of their windows and the instructions whose cycles
    differ most, matched by offset from the start of the window's function. *)

type side = {
  trace : string;
  summary : Window_summary.t;
  window : Text.window;
  commits : Commits.commit list;  (** The whole run's. *)
  base : int;  (** The address that offset 0 is: the entry of the function, or 0. *)
  disasm : int -> string;
}

type stat = { count : int; cycles : int; text : string }
type row = { offset : int; a : stat option; b : stat option }

val rows : top:int -> side -> side -> row list
(** The commits whose retire cycle and PC the window selects, summed by [pc - base]; the [top] with the
    largest difference in cycles charged (B minus A), then by offset. A one-sided offset counts as zero on
    the other side. *)

val row_jsont : row Jsont.t
(** [{"type":"compare.pc","offset","a"?:{"count","cycles","text"},"b"?:…,"delta"}]. *)

val summary_jsont : (Window_summary.t * Window_summary.t) Jsont.t
(** [{"type":"compare.summary","a":{…},"b":{…}}]. *)

val text : top:int -> side -> side -> unit
