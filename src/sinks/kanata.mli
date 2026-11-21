[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** A Kanata log (version 0004), the pipeline view Konata shows: instructions with stages over
    cycles. *)

type stage = {
  name : string;
  lane : int;  (** 0 for the pipeline stages, 1 for stalls drawn over them. *)
  start : int;
  stop : int;  (** Included. *)
}

type insn = {
  label : string;
  detail : string option;  (** The hover text. *)
  stages : stage list;  (** In order, not overlapping. *)
  retired : int option;
  flushed : int option;  (** When neither retires nor flushes it: still in flight at the end. *)
}

(** {1 Writing}

    The lines of an instruction are in cycles from its first stage's start to its retirement or flush, and
    a log lists the lines by cycle, so a line can be written only once no instruction still to come can
    have one before it. A writer is told how far that is by a {e watermark}: a cycle no later
    instruction's first line precedes. The lines before it are written and forgotten, so the memory held is
    that of the instructions between the watermark and their last line, not of the log. *)

module Writer : sig
  type t

  val create : (string -> unit) -> t
  (** Writes the header at once. Instructions are numbered in the order they are added. *)

  val advance : t -> int -> unit
  (** [advance w c] promises that no instruction added from now on starts a stage before cycle [c], and
      writes the lines before it. A smaller [c] than before changes nothing. *)

  val add : t -> insn -> unit
  (** Raises [Invalid_argument] for an instruction whose first stage starts before the watermark, which
      would put its lines out of order. An instruction without stages takes a number and writes nothing. *)

  val finish : t -> unit
  (** Writes what is left. *)
end

val write : out_channel -> insn Seq.t -> unit
(** The instructions in non-decreasing order of the start of their first stage, which is the watermark
    for each: its lines are written as the sequence is pulled. Raises [Invalid_argument] on another
    order. *)

(** The instructions of a run, from the events of [commits] and of [stalls] where the platform has them,
    written as they come. The contract on the input is that the stall spans of an instruction reach the
    builder before its retirement (a span is closed when its instruction dispatches, a cycle before it
    can retire), and that the instructions dispatch in order, as the core's do. *)
module Builder : sig
  type t

  val create : disasm:(int -> string) -> Writer.t -> t
  val stall : t -> Stalls.Event.t -> unit

  val commit : t -> Commits.Event.t -> unit
  (** Each instruction from its commit: [St] in lane 1 for the stall span of its PC that ends the cycle
      before its dispatch, the reason in its tooltip, [Ex] from its dispatch to the cycle before its
      retirement, and the retirement. Retirements without a dispatch are left out. The instructions in
      flight at the end are written by {!finish}. *)

  val finish : t -> unit
  (** The instructions in flight at the end with [Ex] to the end, then a flush record, which Konata needs
      to close them; then {!Writer.finish}. *)
end
