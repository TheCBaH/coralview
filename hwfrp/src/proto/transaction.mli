[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** A request and its response on a bus port, in cycles of the port's clock. *)

type t = {
  id : int;  (** The AXI ID, the TileLink source. *)
  write : bool;
  address : int;
  bytes : int;  (** Moved: for a write, the bytes its strobes or mask enable. *)
  beats : int;
  requested : int;  (** The request was first valid. *)
  accepted : int;  (** The request handshake. *)
  first_data : int option;  (** The first data handshake; a write's can precede [accepted]. *)
  completed : int option;
      (** The last data beat, or the response; [None] if the trace ends first. *)
  status : int;  (** The AXI response, worst of the beats; TileLink: 0, or 2 for [d_error]. *)
  outstanding : int;  (** Transactions of the port outstanding at acceptance, itself included. *)
}

val latency : t -> int option
(** Cycles from acceptance to completion. *)

val span : t -> Span.t
(** From the request to completion. *)

val throughput : t -> float option
(** Bytes per cycle over {!span}. *)
