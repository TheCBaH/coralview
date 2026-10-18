[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Transactions on an AXI4 port, from its five channels.

    Several transactions can be outstanding. They are matched as AXI4 orders them: read data and write
    responses to the oldest outstanding transaction of their ID, and write data, which carries no ID, to
    write addresses in the order they were accepted, whichever came first. *)

type addr = {
  a_fire : bool;
  a_valid : bool;
  a_addr : int;
  a_id : int;
  a_len : int;
  a_size : int;
  a_burst : int;
}

type rdata = { r_fire : bool; r_id : int; r_resp : int; r_last : bool }
type wdata = { w_fire : bool; w_strb : int; w_last : bool }
type bresp = { b_fire : bool; b_id : int; b_resp : int }

(** Each channel's wires, given the channel's name in Chisel's flattening: [<name>_valid],
    [<name>_ready] and [<name>_bits_<field>]. *)

val addr : 'c Hwfrp.Bind.scope -> string -> (addr, 'c) Hwfrp.Sig.t
(** [_bits_addr], [_bits_id], [_bits_len], [_bits_size], [_bits_burst]. *)

val rdata : 'c Hwfrp.Bind.scope -> string -> (rdata, 'c) Hwfrp.Sig.t
(** [_bits_id], [_bits_resp], [_bits_last]. *)

val wdata : 'c Hwfrp.Bind.scope -> string -> data_bytes:int -> (wdata, 'c) Hwfrp.Sig.t
(** [_bits_strb], [data_bytes] wide, and [_bits_last]. *)

val bresp : 'c Hwfrp.Bind.scope -> string -> (bresp, 'c) Hwfrp.Sig.t
(** [_bits_id], [_bits_resp]. *)

type names = {
  read_addr : string;
  write_addr : string;
  read_data : string;
  write_data : string;
  write_resp : string;
}

val chisel : string -> names
(** The channels of Chisel's [AXI4Bundle] under a prefix: [<prefix>read_addr], …, [<prefix>write_resp]. *)

type 'c channels = {
  ar : (addr, 'c) Hwfrp.Sig.t;
  aw : (addr, 'c) Hwfrp.Sig.t;
  r : (rdata, 'c) Hwfrp.Sig.t;
  w : (wdata, 'c) Hwfrp.Sig.t;
  b : (bresp, 'c) Hwfrp.Sig.t;
}

val bind : 'c Hwfrp.Bind.scope -> names -> data_bytes:int -> 'c channels

type extra = {
  serial : int;  (** Acceptance order, from 0. *)
  burst : int;  (** AxBURST. *)
  beat_bytes : int;  (** [1 lsl AxSIZE]. *)
}

type event =
  | Accepted of Hwfrp.Transaction.t * extra
      (** At the address handshake; [completed] is [None], and a write's data may be known already. *)
  | Done of Hwfrp.Transaction.t * extra  (** At the last read data beat, or the write response. *)
  | Open_at_end of Hwfrp.Transaction.t * extra
  | Unmatched of { cycle : int; write : bool; id : int; what : string }
      (** Read data or a write response with no outstanding transaction of its ID, as it comes; write
          data with no write address by the end ([id] is [-1], [cycle] its first beat). *)

type counts = { max_reads : int; max_writes : int  (** Outstanding at once. *) }

val track : ?name:string -> 'c channels -> (event list, 'c) Hwfrp.Ev.t * (counts, 'c) Hwfrp.Sig.t
(** The events of each cycle: responses, then acceptances; then, at the end of the trace, unmatched
    write data and the transactions still outstanding, in acceptance order. In a cycle, a response
    never belongs to an address accepted in that cycle. A {!Hwfrp.Machine} over {!step}. *)

(** {1 The machine, to embed in another} *)

type sample = addr * addr * rdata * wdata * bresp

val sample : 'c channels -> (sample, 'c) Hwfrp.Sig.t

type state
(** Immutable. *)

val init : state
val step : state -> int -> sample -> state * event list
val finish : state -> event list
val counts : state -> counts
