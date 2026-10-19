[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Vector operations as the RVV backend dispatches them ([v_dispatch] block). An instruction counts
    when its first uop is taken, with the [vl] and [vstart] its uops carry: [vl - vstart] elements,
    masked or not. Its kind comes from Rivet's decoding of the word the scalar core dispatched at the
    uop's PC ([dispatch_debug]): fused multiply-adds ([vfmacc], [vfwmacc], [vmacc], ...) are two
    operations an element, other arithmetic one; moves ([vmv*], [vfmv*], [vmerge], [vtmv],
    [vtzero], and the permute unit), memory instructions (the LSU and VME LSU) and [vset*]/[mset*]
    none. A Zvt tile multiply ([vtfmm], [vtmmu], [vtmms]) is [tm * vl * tk] elements of two
    operations, with [tm] and [tk] from its uop.

    Compute instructions separated by more than [gap] idle cycles form separate bursts. *)

type kind = Fma | Arith | Move | Memory | Other  (** Configuration ([vset*]), or not decoded. *)

type op = {
  cycle : int;  (** Of its first uop's dispatch. *)
  pc : int option;  (** When the layout has [uop_pc]. *)
  unit : string;
  mnemonic : string option;  (** Rivet's, from the word the scalar core dispatched at [pc]. *)
  sew : int;  (** Bits. *)
  lmul : string;
  vl : int;
  vstart : int;
  tile : (int * int) option;  (** [tm] and [tk], when the layout has them (Zvt). *)
  kind : kind;
  float : bool;
  elements : int;
  ops : int;
}

type burst = { first : int; last : int; instructions : int; ops : int; flops : int }

val name : string
val doc : string
val needs : string list

module Config : sig
  type t = {
    gap : int;  (** Idle cycles that end a burst. *)
    peak_window : int;  (** Cycles over which the peak rate is taken. *)
    features : string option;  (** Rivet's feature spec, as {!Rivet_decode.create} takes. *)
  }

  val default : t
end

module Event : sig
  type t =
    | Op of op  (** A dispatched vector instruction. *)
    | Burst of burst  (** Emitted once it has ended. *)

  val jsont : t Jsont.t
  val cycle : t -> int
  val pc : t -> int option
end

type unit_total = { u_unit : string; u_instructions : int; u_elements : int; u_ops : int }
type peak = { p_window : int; p_ops : int; p_last : int  (** Last cycle of the window. *) }

module Summary : sig
  type t = {
    cycles : int;
    instructions : int;
    undecoded : int;  (** With no instruction word for their PC, so counted as [Other]. *)
    ops : int;
    flops : int;
    bursts : int;
    busy : int;  (** Cycles inside bursts. *)
    peak : peak option;
    units : unit_total list;
  }

  val jsont : t Jsont.t
end

val build :
  Config.t -> 'c Core.t -> (Event.t list, 'c) Hwfrp.Ev.t * (Hwfrp.Sched.run_stats -> Summary.t)
(** Raises {!Hwfrp.Bind.Unbound} and {!Core.No_block}. *)

val text : Text.ctx -> Event.t list -> Summary.t -> unit
(** Totals by unit, the rates, and the bursts up to the context's limit. *)

val profile : Text.ctx -> Event.t list -> Summary.t -> unit
(** Operations by instruction. *)

val perfetto : Text.ctx -> Event.t list -> Summary.t -> Perfetto.process
(** The bursts, each instruction on its unit's track, and the operations of each peak window as a
    counter. *)
