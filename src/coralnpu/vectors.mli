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
val needs : string list

val graph : ?at:int -> 'c Core.t -> (write -> unit) -> Hwfrp.Sched.run_stats -> summary
(** Raises {!Hwfrp.Bind.Unbound} and {!Core.No_block}. *)

val run : ?at:int -> Platform.t -> Hwfrp.Trace.t -> (write -> unit) -> summary
