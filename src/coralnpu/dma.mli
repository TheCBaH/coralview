[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Jobs of a descriptor DMA engine ([bus.DmaEngine]), from its two TileLink-UL ports. On its CSR port
    software writes [DESC_ADDR] (0x08) and then [CTRL] (0x00) with enable and start (bits 0 and 1), and
    reads [STATUS] (0x04) until done (bit 1, error bit 2). On its host port the engine then fetches the
    descriptor in two 16-byte halves, optionally polls a word, and copies the data one beat at a time,
    each a read followed by a write, before following [next_desc] or finishing.

    The model follows that sequence on the ports and reports what does not fit it. *)

val name : string
val doc : string
val needs : string list

module Config : sig
  type t = { region : Region.t  (** Names the descriptors' source and destination regions. *) }

  val default : t
end

module Descriptor : sig
  type t = {
    at : int;  (** Its address. *)
    src : Access.t;  (** [bytes] is [len]. *)
    dst : Access.t;
    len : int;  (** Bytes. *)
    beat : int;  (** Bytes per beat, [1 lsl xfer_width]. *)
    src_fixed : bool;
    dst_fixed : bool;
    poll : (int * int * int) option;  (** Address, mask and value, when polling is enabled. *)
    next : int;
    fetch : Hwfrp.Span.t;  (** First request and last response of its fetch. *)
  }

  val jsont : t Jsont.t
end

module Event : sig
  type beat = { read : Hwfrp.Transaction.t; write : Hwfrp.Transaction.t option }
  type observed = { cycle : int; pc : int option }

  type job = {
    span : Hwfrp.Span.t;
        (** From the CTRL write that started it to the response that ended it: the last write, an
            error, or [None]. *)
    pc : int option;  (** The instruction that wrote CTRL, from the requester. *)
    first : int;  (** The descriptor address written before. *)
    descriptors : Descriptor.t list;
    beats : beat list;  (** Host port transactions, {!Tlul.to_transaction}. *)
    polls : int;  (** Poll reads by the engine. *)
    error : bool;
    aborted : bool;
    status_reads : int;  (** STATUS reads by software from the start until it saw done. *)
    observed : observed option;  (** When software first read done, and the instruction. *)
  }

  type stray = { cycle : int; what : string }

  type t =
    | Job of job
        (** Once it no longer runs and software saw it done or started another, or at the end: in
            start order. *)
    | Stray of stray  (** Port activity outside the sequence, as it comes. *)

  val jsont : t Jsont.t
  val cycle : t -> int
  val pc : t -> int option
end

val bytes : Event.job -> int
(** Moved: the beats written. *)

module Summary : sig
  type t = {
    cycles : int;
    jobs : int;
    bytes : int;
    max_outstanding : int;  (** On the host port. *)
    stray : int;
  }

  val jsont : t Jsont.t
end

val build :
  Config.t -> 'c Core.t -> (Event.t list, 'c) Hwfrp.Ev.t * (Hwfrp.Sched.run_stats -> Summary.t)

val text : Text.ctx -> beats:int -> Event.t list -> Summary.t -> unit
(** Each job with its first [beats] beats, then the stray activity and the summary. *)
