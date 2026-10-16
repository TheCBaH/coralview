[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Data accesses of the scalar LSU ([core.score.lsu]): the TCM data bus [io_dbus_*] and the external bus
    [io_ebus_dbus_*], with the PC of the LSU slot ([io_ebus_dbus_pc], driven for both) and read data taken
    from the cycle after the request, as [Lsu.scala] registers the response.

    An access is a request that the bus accepted, with the data sampled where the response would be: it
    does not say the access succeeded. The LSU's faults ([io_fault_*]) are reported separately, with the
    request they most likely belong to. *)

type access = {
  cycle : int;  (** Of the request. *)
  bus : [ `Tcm | `External ];
  pc : int;
  addr : int;
  write : bool;
  bytes : int list;
      (** Byte lanes of the 16-byte line: the write mask, or for reads the word at [addr]. *)
  data : Hwfrp.Bits.t;  (** The 128-bit line: write data, or read data one cycle later. *)
}

type fault = {
  f_cycle : int;
  f_pc : int;  (** The faulting instruction ([io_fault_bits_epc]). *)
  f_addr : int;
  f_write : bool;
  request : (int * int) option;
      (** Cycle and address of the last request from that PC in the same direction, at or before the
          fault. *)
}
(** An LSU fault ([io_fault_*]). *)

val model : string

val needs : string list
(** The platform blocks it binds. *)

val graph :
  ?on_fault:(fault -> unit) -> 'c Core.t -> (access -> unit) -> Hwfrp.Sched.run_stats -> unit
(** Builds the model on a bound core; the returned function reads the outcome after the run. Raises
    {!Hwfrp.Bind.Unbound} and {!Core.No_block}. *)

val run : ?on_fault:(fault -> unit) -> Platform.t -> Hwfrp.Trace.t -> (access -> unit) -> unit

val value : access -> int
(** The selected bytes, little-endian. *)
