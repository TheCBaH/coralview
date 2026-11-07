[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** The vector configuration the RVV backend ran each retired vector instruction under, from the [ops]
    events, and a note on the rows of [commits]. *)

val vtype : Ops.op -> string
(** [e32,m4] for an op's SEW and LMUL, in the spelling of [disasm --vconfig]. *)

val join : Commits.commit list -> Ops.op list -> (int * int, Ops.op) Hashtbl.t
(** For each retired commit with a vector op, by (PC, retire cycle), the first op of that PC taken from
    its dispatch up to the next dispatch of the same PC (up to the end of the run for the last). An op of
    an instance that never retired belongs to nobody. *)

val notes :
  static:(int -> string option) ->
  Commits.commit list ->
  Ops.op list ->
  pc:int ->
  cycle:int ->
  string option
(** [e32,m4 vl 16] for a commit with an op, and [ (static e16,m2)] after it when [static pc], the
    configuration [disasm --vconfig] gives the PC, starts with a different vtype. *)
