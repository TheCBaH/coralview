[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** A Coral NPU core in a trace, as its {!Platform.t} describes it: the clock bound at the platform's root,
    and the debug-port lane groups at the sizes the platform gives. Binding raises {!Hwfrp.Bind.Unbound}
    when the trace lacks a signal the description implies. *)

type 'c dep = ..
(** An analysis built in the net, kept for the analyses that depend on it: see {!Analysis.shared}. *)

type 'c t = {
  net : Hwfrp.Net.t;
  trace : Hwfrp.Trace.t;
  clk : 'c Hwfrp.Clock.t;
  platform : Platform.t;
  model : string;
  deps : (string, 'c dep) Hashtbl.t;
}

type any = Any : 'c t -> any

exception No_block of string * string
(** The platform describes no block of that name, which the model needs. *)

val bind : Platform.t -> Hwfrp.Trace.t -> model:string -> any

val block : 'c t -> string -> 'a option -> 'a
(** [block c name (Some b)] is [b]; [None] raises {!No_block}. *)

val scope : 'c t -> string list -> 'c Hwfrp.Bind.scope
(** A block scope, relative to the platform root. *)

val start : 'c t -> Hwfrp.Run.t
(** Compiles the net and starts a run over the whole trace. *)

val run : 'c t -> Hwfrp.Sched.run_stats

type dispatched = { d_lane : int; d_pc : int; d_word : int }

val dispatch : 'c t -> (dispatched option, 'c) Hwfrp.Sig.t list
(** [io_debug_dispatch_N_inst{Fire,Addr,Inst}] of the [dispatch_debug] block. *)

type retired = { r_lane : int; r_pc : int; r_idx : int; r_trap : bool }

val retire : 'c t -> (retired option, 'c) Hwfrp.Sig.t list
(** [io_debug_rb_inst_N_{valid,bits_pc,bits_idx,bits_trap}] of the [retirement_debug] block. [r_idx] is the
    unified destination: x at 0, f at {!float_base}, v at {!vector_base}; {!no_write} and {!store} as the
    retirement buffer encodes them. *)

val float_base : int
val vector_base : int
val no_write : 'c t -> int
val store : 'c t -> int

type write = { reg : int; value : int }

val writes : 'c t -> (write option, 'c) Hwfrp.Sig.t list
(** [io_debug_regfile_writeData_N_*] and, when the platform has the block, [io_debug_float_writeData_N_*],
    with unified register numbers. *)

val present : 'c t -> ('a option, 'c) Hwfrp.Sig.t list -> ('a list, 'c) Hwfrp.Sig.t
(** The [Some] lanes. *)

val reg_name : int -> string
(** [x5], [f3], [v8]. *)
