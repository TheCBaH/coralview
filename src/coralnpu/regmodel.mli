[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** What {!Registers} and {!Vectors} have in common: the relations they check against the recorded
    diagnostics, the storage as of a cycle, and the codecs of their summaries. *)

val relation : (string * int * int) Jsont.t
(** [(code, comparisons, failures)]. *)

val reg : 'v Jsont.t -> (int * 'v) Jsont.t
(** A register and its value. *)

val at : 'v Jsont.t -> (int * (int * 'v) list) Jsont.t
(** The storage as of a cycle. *)

val relations : 'c Core.t -> model:string -> (string * int) list -> (string * int * int) list
(** Each code of [model] with its comparisons made, and its failure count from the net's counts, which
    do not depend on the diagnostics retained. *)

val failures : 'c Core.t -> model:string -> codes:string list -> Hwfrp.Diag.t list
(** The first 20 retained diagnostics of [model] with one of the codes; possibly fewer than counted. *)

val status : (string * int * int) list -> int
(** 1 if a relation failed. *)

val storage_at :
  at:int option -> 'c Core.t -> (_, 'c) Hwfrp.Ev.t list -> (unit -> 's) -> unit -> (int * 's) option
(** [storage_at ~at c changes snapshot] keeps [snapshot ()] as of the last of the [changes] events at or
    before cycle [at]; the result reads it. Nothing is kept without [at]. *)
