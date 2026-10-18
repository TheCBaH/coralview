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

val name : string
val doc : string
val needs : string list

module Config : sig
  type t = unit

  val default : t
end

type retirement = { at : int; trapped : bool }

type fault = {
  cycle : int;
  source : string;  (** [load], [store], [fetch], [rvv], [decode] or [other]. *)
  pc : int;  (** [mepc]. *)
  cause : int;
  value : int;  (** [mtval]. *)
  handler : int;  (** [mtvec] at the fault, mode bits cleared. *)
  csr : int option;
      (** First later cycle where the CSRs hold the fault's cause, PC and value, whether or not they
          already did. *)
  retired_before : retirement option;  (** The faulting PC's last retirement up to the fault. *)
  retired_after : retirement option;  (** Its first retirement after the fault. *)
  dispatched : int option;  (** First dispatch of the handler's first instruction. *)
  delivered : int option;  (** First retirement of it. *)
  until : int;  (** The record's last cycle. *)
}

type csr_change = { c_cycle : int; c_mcause : int; c_mepc : int; c_mtval : int }

module Event : sig
  type t =
    | Fault of fault  (** When its record ends: at the next fault, or at the end. *)
    | Csr_change of csr_change  (** A CSR change that matches no fault, as it comes. *)

  val jsont : t Jsont.t
  val cycle : t -> int
  val pc : t -> int option
end

module Summary : sig
  type t = { cycles : int; faults : int; delivered : int; unmatched : int  (** CSR changes. *) }

  val jsont : t Jsont.t
end

val cause_name : int -> string

val build :
  Config.t -> 'c Core.t -> (Event.t list, 'c) Hwfrp.Ev.t * (Hwfrp.Sched.run_stats -> Summary.t)
(** Raises {!Hwfrp.Bind.Unbound} and {!Core.No_block}. *)

val text : Text.ctx -> Event.t list -> Summary.t -> unit
(** Faults and unmatched CSR changes in cycle order, then the summary. *)
