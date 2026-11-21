[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Data accesses of the scalar LSU ([core.score.lsu]): its one TileLink-UL port [io_tlul_*], which
    reaches the TCMs and the external bus alike, with the PC of the LSU slot ([core.score.lsu.slot]
    [io_pc]). A write is reported at its request, a read when the response brings the data, with the
    cycle of the request.

    An access is a request that the bus accepted: it does not say the access succeeded
    ([d_bits_error] is not reported). The LSU's faults ([io_fault_*]) are reported separately, with the
    request they most likely belong to. *)

val name : string
val doc : string
val needs : string list

module Config : sig
  type t = { region : Region.t }

  val default : t
end

module Event : sig
  type access = {
    cycle : int;  (** Of the request. *)
    pc : int;
    access : Access.t;  (** [bytes]: the byte lanes selected. *)
    lanes : int list;  (** Byte lanes of the data bus: the request's mask. *)
    data : Hwfrp.Bits.t;  (** The data bus: write data, or the response's read data. *)
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

  type unmatched = { cycle : int; source : int }

  type t =
    | Access of access
    | Fault of fault  (** An LSU fault ([io_fault_*]). *)
    | Unmatched of unmatched
        (** A response for a [source] with no request outstanding: it belongs to no access. It has no PC,
            so a window that selects PCs does not select it. *)

  val jsont : t Jsont.t
  val cycle : t -> int
  val pc : t -> int option
end

module Summary : sig
  type t = {
    reads : int;
    writes : int;
    pcs : int;  (** Distinct, of the requests. *)
    faults : int;
    unmatched : int;  (** Responses with no request outstanding; left out of the JSON when 0. *)
  }

  val jsont : t Jsont.t
end

val build :
  Config.t -> 'c Core.t -> (Event.t list, 'c) Hwfrp.Ev.t * (Hwfrp.Sched.run_stats -> Summary.t)

val value : Event.access -> Hwfrp.Bits.t
(** The selected bytes, the first lane least significant, [8 * bytes] bits wide. *)

val text : Text.ctx -> Format.formatter -> (unit -> Summary.t) -> Event.t Text.sink
(** The requests the context selects, up to its limit, and the faults and unmatched responses it selects,
    in the order of the requests' cycles. Memory is held for the limit's requests and for every fault and
    unmatched response. *)

(** The totals of the events: the {!Summary}, in full. *)
module Accumulator : Accumulator.ACCUMULATOR with type event = Event.t and type snapshot = Summary.t
