[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Data accesses of the scalar LSU ([core.score.lsu]): the TCM data bus [io_dbus_*] and the external bus
    [io_ebus_dbus_*], with the PC of the LSU slot ([io_ebus_dbus_pc], driven for both) and read data taken
    from the cycle after the request, as [Lsu.scala] registers the response.

    An access is a request that the bus accepted, with the data sampled where the response would be: it
    does not say the access succeeded. The LSU's faults ([io_fault_*]) are reported separately, with the
    request they most likely belong to. *)

val name : string
val doc : string
val needs : string list

module Config : sig
  type t = { region : Region.t }

  val default : t
end

module Event : sig
  type bus = Tcm | External

  type access = {
    cycle : int;  (** Of the request. *)
    bus : bus;
    pc : int;
    access : Access.t;  (** [bytes]: the byte lanes selected. *)
    lanes : int list;
        (** Byte lanes of the 16-byte line: the write mask, or for reads the word at the address. *)
    data : Hwfrp.Bits.t;  (** The 128-bit line: write data, or read data one cycle later. *)
  }

  type fault = {
    cycle : int;
    pc : int;  (** The faulting instruction ([io_fault_bits_epc]). *)
    address : int;
    write : bool;
    region : string option;
    request : (int * int) option;
        (** Cycle and address of the last request from that PC in the same direction, at or before
            the fault. *)
  }

  type t = Access of access | Fault of fault  (** An LSU fault ([io_fault_*]). *)

  val jsont : t Jsont.t
  val cycle : t -> int
  val pc : t -> int option
end

module Summary : sig
  type t = { reads : int; writes : int; pcs : int;  (** Distinct, of the requests. *) faults : int }

  val jsont : t Jsont.t
end

val build :
  Config.t -> 'c Core.t -> (Event.t list, 'c) Hwfrp.Ev.t * (Hwfrp.Sched.run_stats -> Summary.t)

val value : Event.access -> int
(** The selected bytes, little-endian. *)

val text : Text.ctx -> Event.t list -> Summary.t -> unit
(** The requests the context selects, up to its limit, and the faults it selects. *)

(** The totals of the events: the {!Summary}, in full. *)
module Accumulator : Accumulator.ACCUMULATOR with type event = Event.t and type snapshot = Summary.t
