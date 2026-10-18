[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Retired instructions with their word, destination value and timing, from the debug ports alone: the word
    comes from the dispatch lane (the mini core's retirement buffer reports 0), the value from the register
    file writeback that the retirement's destination index consumes, and every cycle is charged to the oldest
    instruction in flight, so that the charges of a run add up to its cycles. *)

val name : string
val doc : string

val needs : string list
(** The platform blocks it binds. *)

module Config : sig
  type t = unit

  val default : t
end

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

val instance : commit -> Instance.t

type flight = { pc : int; word : int; cycle : int;  (** Of its dispatch. *) charged : int }

module Event : sig
  type t =
    | Commit of commit  (** A retirement; those of a cycle in lane order. *)
    | In_flight of flight  (** Dispatched and not retired by the end, oldest first. *)

  val jsont : t Jsont.t
  (** A commit's PC, word, dispatch and retirement are its [instance]. *)

  val cycle : t -> int
  val pc : t -> int option
end

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

module Summary : sig
  type t = summary

  val jsont : t Jsont.t
end

val build :
  Config.t -> 'c Core.t -> (Event.t list, 'c) Hwfrp.Ev.t * (Hwfrp.Sched.run_stats -> summary)
(** {!shared}. Raises {!Hwfrp.Bind.Unbound} and {!Core.No_block}. *)

val shared : 'c Core.t -> (Event.t list, 'c) Hwfrp.Ev.t * (Hwfrp.Sched.run_stats -> summary)
(** The model, built once per net for the models that depend on it. *)

val events : 'c Core.t -> (commit list, 'c) Hwfrp.Ev.t * (Hwfrp.Sched.run_stats -> summary)
(** The retirements of each cycle, from {!shared}. *)

val commits : Event.t list -> commit list

val profile : Text.ctx -> Event.t list -> Summary.t -> unit
(** The cycles charged by instruction, the [ctx.profile] heaviest PCs. *)

val text : Text.ctx -> Event.t list -> Summary.t -> unit
(** The retirements the context selects, the summary, what was in flight and the profile. *)
