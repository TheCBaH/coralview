[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** The RVV vector register file ([v_registers] block, [rvv_backend_vrf.sv]), kept as a {!Hwfrp.State}
    store and related to its write ports.

    - [storage]: the register file's packed storage.
    - [written]: replayed from the retire unit's write ports ([rt2vrf]) byte by byte, under their byte
      enables; writes to the same register in one cycle are ORed, as the RTL merges them. Every byte
      written so far must hold its last written value one sample later. Bytes never written are not
      compared, so no reset value is assumed.
    - [retired]: a vector instruction the scalar core retires ({!Commits.events}) must be the last to have
      written its destination register before the retirement's cycle.

    Failures are diagnostics with codes [vectors.storage] and [vectors.retired]. *)

type write = {
  cycle : int;
  port : int;
  pc : int option;  (** The writing instruction, when the layout has [uop_pc]. *)
  reg : int;  (** Unified register ({!Core.reg_name}). *)
  strobe : Hwfrp.Bits.t;  (** A byte enable per byte; bit [i] enables byte [i] (bits [8i..8i+7]). *)
  data : Hwfrp.Bits.t;
}

type summary = {
  cycles : int;
  relations : (string * int * int) list;  (** Code, comparisons made, failures. *)
  failures : Hwfrp.Diag.t list;  (** The first 20. *)
  storage : (int * Hwfrp.Bits.t) list;  (** Final storage, by unified register. *)
  storage_at : (int * (int * Hwfrp.Bits.t) list) option;  (** As of the requested cycle. *)
}

val model : string
val name : string
val doc : string
val needs : string list

module Config : sig
  type t = { at : int option  (** Also keep the storage as of this cycle. *) }

  val default : t
end

(** The relation failures are diagnostics, in every JSONL as [diag] lines. *)
module Event : sig
  type t = Vreg_write of write  (** The writes of each cycle, by port. *)

  val jsont : t Jsont.t
  val cycle : t -> int
  val pc : t -> int option
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
(** The first writes, up to the context's limit, the writes by PC, the relations, the storage and the
    first 20 failures. *)
