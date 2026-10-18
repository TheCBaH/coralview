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

val name : string
val doc : string

val needs : string list
(** The platform blocks it binds. *)

module Config : sig
  type t = unit

  val default : t
end

module Event : sig
  type t = Tile_write of write

  val jsont : t Jsont.t
  val cycle : t -> int
  val pc : t -> int option
end

module Summary : sig
  type t = {
    writes : int;
    file : ((int * int) * Hwfrp.Bits.t) list;
        (** The final content of each sub-tile written, by tile and sub-tile. *)
  }

  val jsont : t Jsont.t
end

val build :
  Config.t -> 'c Core.t -> (Event.t list, 'c) Hwfrp.Ev.t * (Hwfrp.Sched.run_stats -> Summary.t)
(** Raises {!Hwfrp.Bind.Unbound} and {!Core.No_block}. *)

val text : Text.ctx -> Event.t list -> Summary.t -> unit
(** The first writes, up to the context's limit, the summary and the writes by PC. *)
