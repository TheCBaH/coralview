[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Retired instructions with their word, destination value and timing, from the debug ports alone: the word
    comes from the dispatch lane (the mini core's retirement buffer reports 0), the value from the register
    file writeback that the retirement's destination index consumes, and every cycle is charged to the oldest
    instruction in flight, so that the charges of a run add up to its cycles. *)

type commit = {
  lane : int;
  pc : int;
  word : int option;  (** [None] when no dispatch matched. *)
  dispatched : int option;  (** Cycle. *)
  written : int option;  (** Cycle of the writeback that supplied [dest]'s value. *)
  retired : int;
  dest : (int * int option) option;  (** Unified register ({!Core.reg_name}) and value. *)
  store : bool;
  trap : bool;
  charged : int;  (** Cycles during which it was the oldest instruction in flight. *)
}

type summary = {
  cycles : int;
  before : int;  (** Cycles before the first dispatch: reset and boot. *)
  empty : int;  (** Later cycles with nothing in flight: the front end is not delivering. *)
  unmatched_retires : int;  (** Retired with no dispatch in flight for its PC. *)
  skipped : int;  (** Dispatched but passed over by a younger retirement. *)
  missing_values : int;  (** Destination with no writeback to consume. *)
  in_flight : int;  (** Dispatched, not retired by the end. *)
  pending : (int * int * int) list;
      (** Those instructions, oldest first: PC, word and dispatch cycle. *)
}

val model : string

val needs : string list
(** The platform blocks it binds. *)

val events : 'c Core.t -> (commit list, 'c) Hwfrp.Ev.t * (Hwfrp.Sched.run_stats -> summary)
(** The retirements of each cycle, in lane order, for other models to build on. *)

val graph : 'c Core.t -> (commit -> unit) -> Hwfrp.Sched.run_stats -> summary
(** Builds the model on a bound core; the returned function reads the outcome after the run. Raises
    {!Hwfrp.Bind.Unbound} and {!Core.No_block}. *)

val run : Platform.t -> Hwfrp.Trace.t -> (commit -> unit) -> summary
