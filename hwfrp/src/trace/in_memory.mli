[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** A trace whose catalog and value changes are values in memory: no file, no parser. A producer that
    holds a simulation's signals builds a catalog with {!scope} and {!var} and supplies its changes as
    events, with the same meaning as the ones a VCD or FST file gives (see [Vcd_ast.event]). *)

val var : ?typ:Vcd_ast.var_type -> id:string -> width:int -> string -> Vcd_ast.var_decl
(** A signal of a scope: a unique [id] (aliases share one), its width in bits, and its name. The type
    defaults to [Wire]. *)

val scope :
  ?typ:Vcd_ast.scope_type ->
  ?children:Vcd_ast.scope_node list ->
  string ->
  Vcd_ast.var_decl list ->
  Vcd_ast.scope_node
(** A named scope (a [Module] by default) with its signals and sub-scopes. *)

val header : Vcd_ast.scope_node list -> Vcd_ast.header
(** A catalog of top-level scopes. *)

val at : int64 -> Vcd_ast.event
(** A timestamp, in the units the producer chose. *)

val change : id:string -> Vcd_types.Value.t -> Vcd_ast.event

val trace : Vcd_ast.header -> Vcd_ast.event Seq.t -> Trace.t
(** The events are consumed lazily and once, in order: a timestamp, then the changes at it. Changes of
    an id the catalog does not declare are dropped, as in a selected read of a file. *)

(** A source that is fed while it is read. *)
module Live : sig
  type t

  val create : Vcd_ast.header -> t
  val trace : t -> Trace.t

  val push : t -> Vcd_ast.event -> unit
  (** Queues one event. Raises [Invalid_argument] after {!finish}. *)

  val finish : t -> unit
  (** No more events will come: a reader that has consumed the queue sees the end. *)

  val queued : t -> int
  (** Events pushed and not yet read. *)
end
