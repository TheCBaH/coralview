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

type origin = {
  issued : int;  (** The cycle the originator's request began. *)
  pc : int option;  (** The instruction that made it, if the originator carries one. *)
  dispatched : int option;  (** When its operation entered the originator's queue: its dispatch. *)
  started : int option;  (** When that operation left the queue to make its requests. *)
  retired : int option;
      (** That instance's retirement, as {!Commits} pairs it with the dispatch; [None] if it had not
          retired by the end, or the originator describes no queue. A store can retire before its
          request is made. *)
  o_addr : int;
  o_write : bool option;
  agrees : bool;
      (** Its address, rounded down to the description's [align], is the AXI address, and its direction
          the transaction's. *)
}

type transaction = {
  write : bool;
  id : int;
  source : string option;  (** The description's name for the ID. *)
  origin : origin option;
      (** [None] when the source has no described origin, or its request was not valid at acceptance. *)
  addr : int;
  beats : int;
  beat_bytes : int;  (** [1 lsl AxSIZE]. *)
  burst : int;
  bytes : int;  (** Bytes moved: for reads [beats * beat_bytes], for writes the strobed bytes. *)
  requested : int;  (** The cycle the address was first valid. *)
  accepted : int;  (** The address handshake. *)
  first_data : int option;
      (** The first data handshake; for a write it can precede [accepted]. [None] if it never came. *)
  completed : int option;
      (** The last read data beat, or the write response; [None] if the trace ends first. *)
  resp : int;  (** The worst response: 0 OKAY, 1 EXOKAY, 2 SLVERR, 3 DECERR. *)
  outstanding : int;  (** Transactions outstanding when this one was accepted, itself included. *)
}

type unmatched = { u_cycle : int; u_write : bool; u_id : int; what : string }
(** A read data beat or write response with no outstanding transaction of its ID, or write data with
    no write to belong to by the end. *)

type summary = {
  cycles : int;  (** Of the trace. *)
  transactions : transaction list;  (** Every transaction, in order of acceptance. *)
  unmatched : unmatched list;
  occupancy : int array;
      (** [occupancy.(k)]: the cycles with [k] transactions outstanding, from the first acceptance to the
          last completion; a transaction is outstanding from its acceptance to its completion, both
          included. *)
  max_reads : int;
  max_writes : int;  (** The most outstanding reads, and writes, at once. *)
  instructions : (int, int) Hashtbl.t;  (** The word of each PC retired or in flight. *)
  resyncs : int;
      (** Queued operations passed over because a younger one issued: flushed, or with no requests. *)
}

val model : string

val needs : string list
(** The platform blocks it binds. *)

val latency : transaction -> int option
(** From acceptance to completion. *)

val start : transaction -> int
(** The originator's request, or else the AXI request. *)

val span : transaction -> int option
(** Cycles from {!start} to completion, both included. *)

val throughput : transaction -> float option
(** [bytes] over {!span}. *)

val resp_name : int -> string

val graph : 'c Core.t -> (transaction -> unit) -> Hwfrp.Sched.run_stats -> summary
(** Builds the model on a bound core, calling the function as each transaction completes; the returned
    function reads the outcome after the run. Raises {!Hwfrp.Bind.Unbound} and {!Core.No_block}. *)

val run : Platform.t -> Hwfrp.Trace.t -> (transaction -> unit) -> summary
