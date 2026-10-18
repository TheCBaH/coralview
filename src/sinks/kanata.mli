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

val write : out_channel -> insn list -> unit
(** Instructions are numbered in list order. *)

val of_run : disasm:(int -> string) -> Commits.Event.t list -> Stalls.Event.t list -> insn list
(** Each instruction from its commit: [St] in lane 1 for the stall span of its PC that ends the cycle
    before its dispatch, the reason in its tooltip, [Ex] from its dispatch to the cycle before its
    retirement, and the retirement; the instructions in flight at the end with [Ex] to the end, then
    a flush record, which Konata needs to close them. Retirements without a dispatch are left out. *)
