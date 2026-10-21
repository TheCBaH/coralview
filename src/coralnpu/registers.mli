[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** The x and f register files, kept as {!Hwfrp.State} stores and related to each other.

    - [storage]: the register file's own registers ([x_registers], [f_registers] blocks; an f register is
      its sign, exponent and mantissa fields).
    - [written]: replayed from the writeback ports; storage must equal it one sample later, when the
      clock edge has stored the write.
    - [scoreboard]: replayed from the dispatch-time marks, the writebacks and pipeline flushes, after
      the RTL's [(scoreboard & ~clr) | set]; the traced [scoreboard] and [flushed_scoreboard] must equal
      it one sample later.
    - [architectural]: replayed from retirements ({!Commits.events}); it must equal storage for every
      register with no write pending on the scoreboard and none written but unretired.

    Failures are diagnostics with codes [registers.storage], [registers.scoreboard],
    [registers.flushed] and [registers.architectural]. *)

type summary = {
  cycles : int;
  relations : (string * int * int) list;  (** Code, comparisons made, failures. *)
  flushes : int;  (** Samples with a pipeline flush, counted per register file. *)
  failures : Hwfrp.Diag.t list;  (** The first 20. *)
  storage : (int * int) list;  (** Final storage, by unified register. *)
  architectural : (int * int) list;
  storage_at : (int * (int * int) list) option;  (** The storage as of the requested cycle. *)
}

val model : string
val name : string
val doc : string
val needs : string list

module Config : sig
  type t = { at : int option  (** Also keep the storage as of this cycle. *) }

  val default : t
end

(** The register files as events. The failures of the relations are still diagnostics, in every JSONL as
    [diag] lines. *)
module Event : sig
  type write = { cycle : int; reg : int; value : int }
  (** A change of the register file's own storage: [reg] is the unified register ({!Core.reg_name}). The
      first sample has one for every register, which is the initial state. *)

  type flush = { cycle : int; file : string  (** ["x"] or ["f"]. *) }
  (** A sample with a pipeline flush in a register file. *)

  type checks = {
    cycle : int;
    relations : (string * int * int) list;  (** Code, comparisons, failures. *)
  }
  (** The comparisons made and failed over the whole trace, once, at its end. *)

  type t = Write of write | Flush of flush | Checks of checks

  val jsont : t Jsont.t
  val cycle : t -> int

  val pc : t -> int option
  (** Always [None]. *)
end

module Summary : sig
  type t = summary

  val jsont : t Jsont.t
end

val build :
  Config.t -> 'c Core.t -> (Event.t list, 'c) Hwfrp.Ev.t * (Hwfrp.Sched.run_stats -> summary)
(** Raises {!Hwfrp.Bind.Unbound} and {!Core.No_block}. *)

val status : summary -> int
(** 1 if a relation failed. *)

val text : Text.ctx -> Event.t list -> summary -> unit
(** The relations, the storage tables and the first failures, up to the context's limit. *)

(** The events received: the storage they write, the flushes and, once it has arrived, the comparison
    counts. The comparisons are made at every sample but reported at the end of the trace, so a snapshot
    before it has [relations = []]. The architectural values are not here: they are the retirements of
    {!Commits}. *)
module Accumulator : sig
  type snapshot = {
    writes : int;
    flushes : int;
    relations : (string * int * int) list;
    storage : (int * int) list;  (** By unified register. *)
  }

  include Accumulator.ACCUMULATOR with type event = Event.t and type snapshot := snapshot

  val snapshot_jsont : snapshot Jsont.t
end
