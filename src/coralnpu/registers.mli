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
val needs : string list
val graph : ?at:int -> 'c Core.t -> Hwfrp.Sched.run_stats -> summary
val run : ?at:int -> Platform.t -> Hwfrp.Trace.t -> summary
