[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** Loops found in the retired instructions, from their backward branches. *)

type trip = {
  start : int;  (** Retire cycle of the trip's first instruction. *)
  instructions : int;
  cycles : int;  (** The cycles charged to the trip's instructions. *)
}

type pc_stat = {
  pc : int;
  word : int option;
  count : int;  (** Retirements of the PC over all trips. *)
  cycles : int;  (** Cycles charged to them. *)
}

type loop = {
  header : int;  (** The target of the backward branches. *)
  tail : int;  (** The last of the PCs that branch back to it. *)
  trips : trip list;  (** In order. *)
  body : pc_stat list;  (** The PCs retired in the trips, ascending. *)
}

val detect : Commits.commit list -> loop list
(** The retirements in program order. A [jal x0] or a conditional branch followed by a retirement at a PC
    at or below its own is a backward branch to that PC; a trip is the retirements from the last one at the
    header up to and including the branch. A loop is found by a taken backward branch; its last trip, which
    leaves through the same branch not taken, or ends the run, is counted too. A loop left through another exit adds no
    trip for that run. Nested loops each have their own trips; an
    outer trip contains the inner ones. Loops by total cycles, descending. *)

val median : int list -> int
(** The lower middle of the sorted list; 0 when empty. *)

val loop_jsont : loop Jsont.t
(** [{"type":"loops.loop","header","tail","trips":[{"start","instructions","cycles"}],"pcs":[{"pc","word"?,
    "count","cycles"}]}]; the statistics are the reader's to compute from the trips. *)

val text : disasm:(int -> string) -> symbol:(int -> (string * int) option) -> loop list -> unit
(** One block a loop: header, back-edge PC, trips, instructions and cycles a trip (median, range), then
    each PC's mean cycles a trip. *)
