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

val reasons : reason list
(** In the order of [canDispatch]: the text table's order. *)

type lane = { lane : int; pc : int; word : int; reason : reason }

val name : string
val doc : string

val needs : string list
(** The platform blocks it binds. *)

module Config : sig
  type t = unit

  val default : t
end

module Event : sig
  type stall_span = { lane : int; reason : reason; pc : int; word : int; span : Hwfrp.Span.t }

  type t =
    | Stall_span of stall_span
        (** A maximal run of cycles in which a lane had the same reason and instruction, once it ends;
            those still running at the end come last, open. *)

  val reason : reason Jsont.t
  val jsont : t Jsont.t
  val cycle : t -> int
  val pc : t -> int option
end

module Summary : sig
  type count = { lane : int; reason : reason; cycles : int }
  type t = { cycles : int; counts : count list  (** By lane, then reason. *) }

  val jsont : t Jsont.t
end

val build :
  Config.t -> 'c Core.t -> (Event.t list, 'c) Hwfrp.Ev.t * (Hwfrp.Sched.run_stats -> Summary.t)
(** Raises {!Hwfrp.Bind.Unbound} and {!Core.No_block}. *)

val text : Text.ctx -> Event.t list -> Summary.t -> unit
(** The cycles of each reason per lane, and the profile of lane 0's blocked cycles by instruction. *)
