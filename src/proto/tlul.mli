[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Transactions on a TileLink-UL port: a request on channel A and its response on channel D, matched by
    source ID, which TileLink keeps unique among outstanding requests. *)

type request = {
  opcode : int;  (** 0 PutFullData, 1 PutPartialData, 4 Get. *)
  size : int;  (** Bytes, [1 lsl a_size]. *)
  source : int;
  address : int;
  mask : int;
  data : Hwfrp.Bits.t;
}

type transaction = {
  request : request;
  requested : int;  (** The cycle A was first valid. *)
  accepted : int;  (** The A handshake. *)
  responded : int option;  (** The D handshake. *)
  response : Hwfrp.Bits.t;  (** D data: what a Get read. *)
  error : bool;
  outstanding : int;  (** Requests outstanding at acceptance, itself included. *)
}

val is_get : request -> bool

val value : data_bytes:int -> request -> Hwfrp.Bits.t -> int
(** The [request.size] bytes at the request's address in a data bus of [data_bytes], little-endian;
    at most 8. *)

type event =
  | Accepted of transaction
  | Responded of transaction
  | Unmatched of int  (** A response for a source with nothing outstanding. *)

type 'c t

type names = {
  prefix : string;
      (** Of the channel wires: [a_valid], [a_ready], [a_bits_{opcode,size,source,address,mask,data}],
          [d_valid], [d_ready], [d_bits_{source,data,error}]. *)
  d_ready : bool;  (** [false] for a device that does not read it: a response is taken when valid. *)
}

val bind : 'c Hwfrp.Bind.scope -> names -> data_bytes:int -> 'c t
(** A port with a [data_bytes]-wide data bus. Raises {!Hwfrp.Bind.Unbound}. *)

type sample

val sample : 'c t -> (sample, 'c) Hwfrp.Sig.t

type state
(** The requests outstanding: an immutable value. *)

val init : state

val step : 'c t -> state -> int -> sample -> state * event list
(** Advances the port by one cycle, given its sample: that cycle's acceptance and then its response. *)

val max_outstanding : state -> int

val to_transaction : transaction -> Hwfrp.Transaction.t
(** [id] is the source, [bytes] the request size, [status] 2 for [d_error]; a Get's data comes with the
    response, a Put's with the request. *)
