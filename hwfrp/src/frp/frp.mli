[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** A synchronous dataflow graph evaluated once per clock-domain sample. The phantom ['c] names the clock
    domain, so the inputs of a node share its domain at compile time. Events become signals only through
    {!Sig.hold}, {!Sig.fold} and {!Machine.run}. *)

module Net : sig
  type t

  val create : unit -> t

  val domains : t -> Trace.domain_spec array
  (** The specs of the defined clocks, in definition order: pass them to {!Sampler.create}. *)

  type ext = ..
  (** Data that libraries such as [Bind] keep with a net. *)

  val add_ext : t -> ext -> unit
  val exts : t -> ext list

  val add_check : t -> (unit -> string list) -> unit
  (** Run by {!Sched.compile}, which fails with one [Check_failed] per returned message. *)
end

module Clock : sig
  type 'c t
  type any = Any : 'c t -> any

  val define : Net.t -> name:string -> Trace.domain_spec -> any
  val name : 'c t -> string
end

type ('a, 'c) signal
type ('a, 'c) event

module Sig : sig
  type ('a, 'c) t = ('a, 'c) signal

  val const : 'c Clock.t -> 'a -> ('a, 'c) t

  val map : ?name:string -> ?eq:('b -> 'b -> bool) -> ('a -> 'b) -> ('a, 'c) t -> ('b, 'c) t
  (** [eq] decides whether a recomputed value is a change; it defaults to physical equality. *)

  val map2 :
    ?name:string ->
    ?eq:('r -> 'r -> bool) ->
    ('a -> 'b -> 'r) ->
    ('a, 'c) t ->
    ('b, 'c) t ->
    ('r, 'c) t

  val ( let+ ) : ('a, 'c) t -> ('a -> 'b) -> ('b, 'c) t
  val ( and+ ) : ('a, 'c) t -> ('b, 'c) t -> ('a * 'b, 'c) t
  val all : ('a, 'c) t list -> ('a list, 'c) t

  val pre : init:'a -> ('a, 'c) t -> ('a, 'c) t
  (** The value at the previous sample of the domain; [init] at the first. *)

  val hold : init:'a -> ('a, 'c) event -> ('a, 'c) t
  val fold : ?name:string -> init:'s -> ('s -> 'a -> 's) -> ('a, 'c) event -> ('s, 'c) t

  val changes : ?eq:('a -> 'a -> bool) -> ('a, 'c) t -> ('a, 'c) event
  (** Fires with the new value when it differs from the previous sample's; never at the first sample. *)

  val cycle : 'c Clock.t -> (int, 'c) t
  val time : 'c Clock.t -> (Vcd_types.Timestamp.t, 'c) t
  val enabled : 'c Clock.t -> (bool, 'c) t

  val peek : ('a, 'c) t -> 'a
  (** The current value, for subscribers and tests. *)
end

module Ev : sig
  type ('a, 'c) t = ('a, 'c) event

  val never : 'c Clock.t -> ('a, 'c) t
  val map : ('a -> 'b) -> ('a, 'c) t -> ('b, 'c) t
  val filter : ('a -> bool) -> ('a, 'c) t -> ('a, 'c) t
  val filter_map : ('a -> 'b option) -> ('a, 'c) t -> ('b, 'c) t

  val when_ : (bool, 'c) Sig.t -> ('a, 'c) Sig.t -> ('a, 'c) t
  (** Fires with the signal's value at every sample where the condition holds. *)

  val rising : (bool, 'c) Sig.t -> (unit, 'c) t
  val falling : (bool, 'c) Sig.t -> (unit, 'c) t
  val merge : ('a -> 'a -> 'a) -> ('a, 'c) t -> ('a, 'c) t -> ('a, 'c) t

  val union : ('a, 'c) t list -> ('a list, 'c) t
  (** The occurrences of one sample, in list order. *)

  val tag : ('b, 'c) Sig.t -> ('a, 'c) t -> ('a * 'b, 'c) t
  val scan : init:'s -> ('s -> 'a -> 's * 'b option) -> ('a, 'c) t -> ('b, 'c) t

  val flatten : ('a list, 'c) t -> ('a list, 'c) t
  (** Drops empty lists. *)

  val gather : ('a option, 'c) Sig.t list -> ('a list, 'c) t
  (** Fires at every sample where some of the signals are [Some], with their values in list order: the
      valid lanes of a cycle. *)

  val subscribe : ('a, 'c) t -> ('a -> unit) -> unit
  (** Runs after the sample has settled, in registration order. *)
end

module Machine : sig
  type ('s, 'i, 'o) spec = {
    name : string;
    init : 's;
    step : tick:Trace.tick -> 's -> 'i -> 's * 'o list;
    finish : 's -> 'o list;
        (** Emitted at the end of the trace, through the events and signals downstream; no machine steps then. *)
    every_tick : bool;  (** Step even when the input did not change. *)
  }

  val run : ('s, 'i, 'o) spec -> ('i, 'c) Sig.t -> ('o list, 'c) Ev.t * ('s, 'c) Sig.t
end

module Source : sig
  val logic :
    ?name:string ->
    ?eq:('a -> 'a -> bool) ->
    'c Clock.t ->
    Trace.signal ->
    init:'a ->
    (Logic.t -> 'a) ->
    ('a, 'c) Sig.t
  (** A tracked signal decoded at every sample where it changed. *)

  val value :
    ?name:string ->
    ?eq:('a -> 'a -> bool) ->
    'c Clock.t ->
    Trace.signal ->
    init:'a ->
    (Vcd_types.Value.t -> 'a) ->
    ('a, 'c) Sig.t
end

module Clock_cross : sig
  val resample : ('a, 'c1) Sig.t -> 'c2 Clock.t -> ('a, 'c2) Sig.t
  (** The last value seen, read at every sample of the second domain. *)
end

module Diag : sig
  type severity = Error | Warning | Info

  type t = {
    severity : severity;
    source : string;
    code : string;  (** Stable, e.g. ["decoupled.payload-changed"]. *)
    cycle : int option;
    time : Vcd_types.Timestamp.t option;
    paths : Vcd_types.Reference.t list;  (** Where to look in the waveform. *)
    message : string;
  }

  val make :
    ?severity:severity ->
    ?paths:Vcd_types.Reference.t list ->
    source:string ->
    code:string ->
    string ->
    t
  (** [cycle] and [time] are filled in from the sample when {!emit} records it. *)

  val report : Net.t -> t -> unit
  (** Records a diagnostic during a sample, from inside a node function. *)

  val emit : Net.t -> ('a, 'c) Ev.t -> ('a -> t option) -> unit

  val stream : Net.t -> t Seq.t
  (** The recorded diagnostics, oldest first, at most [max_diags] of them. *)

  val dropped : Net.t -> int
  val max_diags : int ref
  val pp : Format.formatter -> t -> unit
end

module Sched : sig
  type t
  type node_stats = { evals : int; changes : int }
  type build_error = Unbound_source of string | Check_failed of string

  type strategy =
    | Incremental  (** Evaluates the nodes reached from what changed, in id order, from a heap. *)
    | Sweep  (** Scans every node of the domain for a changed input: the reference for tests. *)

  type run_stats = {
    ticks : int array;  (** Per domain. *)
    node_evals : int;
    wall_s : float;
    per_node : (string * node_stats) list;
  }

  val compile : ?strategy:strategy -> Net.t -> (t, build_error list) result
  (** Runs the checks of {!Net.add_check}, then freezes the net: no node can be added afterwards. *)

  val run : t -> Sampler.t -> run_stats
  (** The sampler must have been created with {!Net.domains}. *)

  val dump_dot : t -> out_channel -> unit
end
