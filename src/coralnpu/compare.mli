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

type loop_stat = {
  header : int;  (** Offset of the loop's header from the window's function. *)
  trips : int;
  instructions : int;  (** Median over the trips. *)
  cycles_per_trip : int;  (** Median over the trips. *)
  cycles : int;  (** Over all trips. *)
}

type loop_row = { rank : int; a : loop_stat option; b : loop_stat option }

val loop_rows : top:int -> side -> side -> loop_row list
(** The loops of the two windows ({!Loops.detect}), each side ordered by cycles in the loop, paired by
    that rank, so kernels whose layouts differ (an unrolled loop against a one-trip loop) still line up by
    their hot loops. At most [top] pairs; a side with fewer loops has [None]. *)

val loop_row_jsont : loop_row Jsont.t
(** [{"type":"compare.loop","rank","a"?:{"header","trips","instructions","cycles_per_trip","cycles"},"b"?:…,
    "delta"}], the delta being B's cycles in the loop minus A's. *)

val text_loops : top:int -> side -> side -> unit
