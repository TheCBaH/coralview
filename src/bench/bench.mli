[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Where the time goes on a trace: decoding its value changes, all of them and then the sampled
    signals' only, opening it (hierarchy), sampling the signals declared at the platform root on
    its clock, and evaluating a seeded synthetic graph of [nodes] operators over them with each
    {!Hwfrp.Sched.strategy}. Without [select], the trace is read whole at every stage. *)

val run : Platform.t -> select:bool -> nodes:int -> string -> unit
