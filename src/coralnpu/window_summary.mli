[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** The figures of one window of a run, from the events of the models, for tests and for [compare]. *)

type hot_loop = {
  header : int;  (** The loop's header PC. *)
  trips : int;
  cycles_per_trip : int;  (** The median over the trips. *)
}

type t = {
  first : int;  (** The window's first cycle. *)
  last : int option;  (** Absent when unbounded. *)
  instructions : int;  (** Retired in the window. *)
  cycles : int;  (** Charged to them. *)
  loads : int option;  (** Data read requests; absent without the [memory] model. *)
  stores : int option;  (** Data write requests. *)
  vector_instructions : int option;  (** Absent without the [ops] model. *)
  vector_ops : int option;
  stalls : (string * int) list option;
      (** Lane-cycles by dispatch reason, those that happened, in the order of {!Stalls.reasons}; absent
          without the [stalls] model. *)
  hot_loop : hot_loop option;
      (** The loop with the most cycles in the window, from {!Loops.detect}; absent when there is none. *)
}

val make :
  window:Text.window ->
  end_cycle:int ->
  commits:Commits.commit list ->
  accesses:Memory.Event.access list option ->
  ops:Ops.op list option ->
  stalls:Stalls.Event.stall_span list option ->
  t
(** Commits, accesses and ops are those whose cycle (retire or request) and PC the window selects; a
    stall span counts the cycles it has inside the window. [end_cycle] closes a span still open at the
    end of the run. *)

val of_trace : Platform.t -> window:Text.window -> ?region:Region.t -> Hwfrp.Trace.t -> t
(** One pass over the trace, whatever its source: a file, a pipe or {!Hwfrp.In_memory} events. The models are
    those whose blocks the platform describes; [commits] is required. Raises as {!Analysis.S.build}. *)

val analyze :
  Platform.t -> window:Text.window -> ?region:Region.t -> Hwfrp.Trace.t -> t * Commits.commit list
(** {!of_trace} and the trace's whole list of retired instructions. *)

val jsont : t Jsont.t
(** [{"type":"summary.window","first","last"?,"instructions","cycles","loads"?,"stores"?,
    "vector_instructions"?,"vector_ops"?,"stalls"?:[{"reason","lane_cycles"}],
    "hot_loop"?:{"header","trips","cycles_per_trip"}}]. *)

val text : t -> unit
