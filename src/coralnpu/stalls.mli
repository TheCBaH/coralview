[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Why each dispatch lane did or did not dispatch, cycle by cycle, from the scalar core's [Dispatch] module
    ([core.score.dispatch]): its inputs, its [tryDispatch]/[lastReady] wires and the scoreboards, classified
    in the order of [canDispatch] in [scalar/Decode.scala]. *)

type reason =
  | Dispatched
  | Empty  (** No instruction from fetch. *)
  | Behind  (** An older lane did not dispatch: dispatch is in order. *)
  | Halted
  | Interlock
  | Raw  (** A source register is still being written (scoreboard). *)
  | Waw  (** The destination is still being written. *)
  | Float_hazard
  | Lsu_queue
  | Rvv_queue
  | Rob_full
  | Trap_pending
  | Csr_serialize  (** CSR access waits for the retirement buffer to drain. *)
  | Unit_busy  (** Allowed, but the execution unit was not ready. *)
  | Other
      (** Blocked by a rule not reconstructed here (jump, branch, fence, slot 0, RVV config). *)

val reason_name : reason -> string

type lane = { lane : int; pc : int; word : int; reason : reason }

val model : string

val needs : string list
(** The platform blocks it binds. *)

val graph : 'c Core.t -> (int -> lane list -> unit) -> Hwfrp.Sched.run_stats -> int
(** Builds the model on a bound core; the returned function reads the outcome after the run. Raises
    {!Hwfrp.Bind.Unbound} and {!Core.No_block}. *)

val run : Platform.t -> Hwfrp.Trace.t -> (int -> lane list -> unit) -> int
