[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Where the time goes on a trace: decoding its value changes, opening it (hierarchy), sampling the signals declared at the platform root on its clock, and evaluating a seeded synthetic graph of [nodes] operators over them with each
    {!Hwfrp.Sched.strategy}. *)

val run : Platform.t -> nodes:int -> string -> unit
