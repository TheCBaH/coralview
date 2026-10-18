[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Jobs of a descriptor DMA engine ([bus.DmaEngine]), from its two TileLink-UL ports. On its CSR port
    software writes [DESC_ADDR] (0x08) and then [CTRL] (0x00) with enable and start (bits 0 and 1), and
    reads [STATUS] (0x04) until done (bit 1, error bit 2). On its host port the engine then fetches the
    descriptor in two 16-byte halves, optionally polls a word, and copies the data one beat at a time,
    each a read followed by a write, before following [next_desc] or finishing.

    The model follows that sequence on the ports and reports what does not fit it. *)

type descriptor = {
  at : int;  (** Its address. *)
  src : int;
  dst : int;
  len : int;  (** Bytes. *)
  beat : int;  (** Bytes per beat, [1 lsl xfer_width]. *)
  src_fixed : bool;
  dst_fixed : bool;
  poll : (int * int * int) option;  (** Address, mask and value, when polling is enabled. *)
  next : int;
  fetch : int * int;  (** First request and last response of its fetch. *)
}

type beat = { read : Tlul.transaction; write : Tlul.transaction option }

type job = {
  started : int;  (** The CTRL write that started it. *)
  pc : int option;  (** The instruction that wrote CTRL, from the requester. *)
  first : int;  (** The descriptor address written before. *)
  descriptors : descriptor list;
  beats : beat list;
  polls : int;  (** Poll reads by the engine. *)
  finished : int option;  (** The response that ended it: the last write, an error, or [None]. *)
  error : bool;
  aborted : bool;
  status_reads : int;  (** STATUS reads by software from the start until it saw done. *)
  observed : (int * int option) option;  (** When software first read done, and the instruction. *)
}

val bytes : job -> int
(** Moved: the beats written. *)

val latency : job -> int option
(** From start to finish. *)

type summary = {
  cycles : int;
  jobs : job list;
  stray : (int * string) list;  (** Port activity outside the sequence: cycle and what. *)
  max_outstanding : int;  (** On the host port. *)
}

val model : string
val needs : string list
val graph : 'c Core.t -> Hwfrp.Sched.run_stats -> summary
val run : Platform.t -> Hwfrp.Trace.t -> summary
