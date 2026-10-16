[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Faults and their delivery ([traps] block), from three separate observations that a report must not
    merge:

    - the fault manager asserting a fault, with the cause, PC and value it sends to the CSRs;
    - the CSRs [mcause], [mepc] and [mtval] taking those values;
    - the trap being delivered: the handler at [mtvec] retiring.

    Each is matched to a fault by explicit validity and PC, never by assuming that a request faults or
    that a CSR change is a new fault. A fault's record ends at the next fault or at the end of the trace. *)

type retirement = { at : int; trapped : bool }

type fault = {
  cycle : int;
  source : string;  (** [load], [store], [fetch], [rvv], [decode] or [other]. *)
  pc : int;  (** [mepc]. *)
  cause : int;
  value : int;  (** [mtval]. *)
  handler : int;  (** [mtvec] at the fault, mode bits cleared. *)
  mutable csr : int option;
      (** First later cycle where the CSRs hold the fault's cause, PC and value, whether or not they
          already did. *)
  mutable retired_before : retirement option;
      (** The faulting PC's last retirement up to the fault. *)
  mutable retired_after : retirement option;  (** Its first retirement after the fault. *)
  mutable dispatched : int option;  (** First dispatch of the handler's first instruction. *)
  mutable delivered : int option;  (** First retirement of it. *)
  mutable until : int;  (** The record's last cycle. *)
}

type csr_change = { c_cycle : int; c_mcause : int; c_mepc : int; c_mtval : int }

type summary = {
  cycles : int;
  faults : fault list;  (** In order. *)
  unmatched : csr_change list;  (** CSR changes that match no fault. *)
}

val model : string
val needs : string list
val cause_name : int -> string

val graph : 'c Core.t -> Hwfrp.Sched.run_stats -> summary
(** Raises {!Hwfrp.Bind.Unbound} and {!Core.No_block}. *)

val run : Platform.t -> Hwfrp.Trace.t -> summary
