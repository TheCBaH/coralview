[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Writes into the VME tile register file ([backend.vme], [zvt.sv]): per block (4) and port (4), the byte
    enables [writeEn], tile [writeMtIdx], sub-tile [writeSubIdx] and 16-byte [writeData]. A write whose
    enables equal the PE array's [peWriteEn] comes from the PE array and carries its block's [peWritePc];
    the others (tile loads) have no PC here. *)

type write = {
  cycle : int;
  block : int;
  port : int;
  pc : int option;
  tile : int;
  sub : int;
  mask : int;  (** Byte enables of the 16-byte sub-tile. *)
  data : Hwfrp.Bits.t;
}

val model : string

val needs : string list
(** The platform blocks it binds. *)

val graph :
  'c Core.t -> (write -> unit) -> Hwfrp.Sched.run_stats -> (int * int, Hwfrp.Bits.t) Hashtbl.t
(** Builds the model on a bound core; the returned function reads the outcome after the run. Raises
    {!Hwfrp.Bind.Unbound} and {!Core.No_block}. *)

val run : Platform.t -> Hwfrp.Trace.t -> (write -> unit) -> (int * int, Hwfrp.Bits.t) Hashtbl.t
