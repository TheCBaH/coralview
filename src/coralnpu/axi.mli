[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Transactions on the core's AXI4 master port ([CoreAxi.io_axi_master]), which carries all of its
    external traffic: the LSU's external bus ([DBus2Axi]: scalar, vector and tile loads and stores
    outside the TCMs) and instruction fetches outside the ITCM ([IBus2Axi]).

    Several transactions can be outstanding. They are matched as AXI4 orders them: read data and write
    responses to the oldest outstanding transaction of their ID, and write data, which carries no ID, to
    write addresses in the order they were accepted, whichever came first.

    Each transaction is pinned to its originator: the AXI ID names the master (the description's
    [sources]), and the master's own request interface, valid when the address is accepted, gives the
    request it serves, when it began and the instruction that made it. Where the description gives the
    originator's in-order operation queue, the request is pinned further to the instance of that
    instruction: the latest operation of its PC to issue, which is matched to its dispatch through the
    queue and to its retirement through {!Commits}. A vector or tile access makes several requests, all
    pinned to the same instance. *)

val name : string
val doc : string

val needs : string list
(** The platform blocks it binds. *)

module Config : sig
  type t = { region : Region.t  (** Names the transactions' regions in the events. *) }

  val default : t
end

(** The originator's request that a transaction serves. *)
module Origin : sig
  type t = {
    issued : int;  (** The cycle the originator's request began. *)
    request : int;  (** Its address. *)
    write : bool option;
    agrees : bool;
        (** Its address, rounded down to the description's [align], is the AXI address, and its
            direction the transaction's. *)
    instance : Instance.t option;
        (** The instruction, if the originator carries a PC: [dispatched] is when its operation
            entered the originator's queue, [issued] when it left it to make its requests, [retired]
            its retirement as {!Commits} pairs it with the dispatch. A store can retire before its
            request is made. *)
  }

  val jsont : t Jsont.t
end

module Event : sig
  type transaction = {
    txn : Hwfrp.Transaction.t;
    source : string option;  (** The description's name for the ID. *)
    region : string option;
    origin : Origin.t option;
        (** [None] when the source has no described origin, or its request was not valid at
            acceptance. *)
    burst : int;
    beat_bytes : int;  (** [1 lsl AxSIZE]. *)
  }

  type unmatched = { cycle : int; write : bool; id : int; what : string }

  type t =
    | Transaction of transaction
        (** In acceptance order, once complete and its instance retired, or at the end. *)
    | Unmatched of unmatched
        (** A read data beat or write response with no outstanding transaction of its ID, or write
            data with no write to belong to by the end. *)

  val jsont : t Jsont.t
  val cycle : t -> int
  val pc : t -> int option
end

module Summary : sig
  type source = {
    id : int;
    source : string;
    transactions : int;
    bytes : int;
    pinned : int;  (** To a request. *)
    instances : int;  (** To an instruction instance. *)
    disagreeing : int;
  }

  type t = {
    cycles : int;
    reads : int;
    read_bytes : int;
    writes : int;
    write_bytes : int;
    unmatched : int;
    read_latency : Hwfrp.Reduce.Stats.t;  (** Address accepted to done. *)
    write_latency : Hwfrp.Reduce.Stats.t;
    incomplete : int;  (** Not done when the trace ends. *)
    first : int option;  (** The earliest {!start}. *)
    last : int option;  (** The latest completion, the last cycle for those not done. *)
    occupancy : int list;
        (** The [k]th: the cycles with [k] transactions outstanding, from the first acceptance to the
            last completion; a transaction is outstanding from its acceptance to its completion, both
            included. *)
    max_reads : int;
    max_writes : int;  (** The most outstanding reads, and writes, at once. *)
    sources : source list;  (** By ID. *)
    resyncs : int;
        (** Queued operations passed over because a younger one issued: flushed, or with no
            requests. *)
    words : (int * int) list;  (** The word of each PC the transactions are pinned to. *)
  }

  val jsont : t Jsont.t
end

val build :
  Config.t -> 'c Core.t -> (Event.t list, 'c) Hwfrp.Ev.t * (Hwfrp.Sched.run_stats -> Summary.t)
(** Raises {!Hwfrp.Bind.Unbound} and {!Core.No_block}. *)

val start : Event.transaction -> int
(** The originator's request, or else the AXI request. *)

val span : Event.transaction -> int option
(** Cycles from {!start} to completion, both included. *)

val throughput : Event.transaction -> float option
(** [bytes] over {!span}. *)

val resp_name : int -> string

val text : Text.ctx -> Event.t list -> Summary.t -> unit
(** The rows the context selects, the unmatched ones, the summary and the profile by instruction. *)
