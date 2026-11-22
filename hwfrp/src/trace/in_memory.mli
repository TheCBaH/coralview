[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-sonnet-5-5"]
[@@@ai_provider "Anthropic"]

(** A trace whose catalog and value changes are values in memory: no file, no parser. A producer that
    holds a simulation's signals builds a catalog with {!scope} and {!var} and supplies its changes as
    events, with the same meaning as the ones a VCD or FST file gives (see [Ovcd.Ast.event]). *)

val var : ?typ:Ovcd.Ast.var_type -> id:string -> width:int -> string -> Ovcd.Ast.var_decl
(** A signal of a scope: a unique [id] (aliases share one), its width in bits, and its name. The type
    defaults to [Wire]. *)

val scope :
  ?typ:Ovcd.Ast.scope_type ->
  ?children:Ovcd.Ast.scope_node list ->
  string ->
  Ovcd.Ast.var_decl list ->
  Ovcd.Ast.scope_node
(** A named scope (a [Module] by default) with its signals and sub-scopes. *)

val header : Ovcd.Ast.scope_node list -> Ovcd.Ast.header
(** A catalog of top-level scopes. *)

val at : int64 -> Ovcd.Ast.event
(** A timestamp, in the units the producer chose. *)

val change : id:string -> Ovcd_types.Value.t -> Ovcd.Ast.event

val trace : Ovcd.Ast.header -> Ovcd.Ast.event Seq.t -> Trace.t
(** The events are consumed lazily and once, in order: a timestamp, then the changes at it. Changes of
    an id the catalog does not declare are dropped, as in a selected read of a file. *)

(** A source that is fed while it is read. *)
module Live : sig
  type t

  val create : Ovcd.Ast.header -> t
  val trace : t -> Trace.t

  val push : t -> Ovcd.Ast.event -> unit
  (** Queues one event. Raises [Invalid_argument] after {!finish}. *)

  val finish : t -> unit
  (** No more events will come: a reader that has consumed the queue sees the end. *)

  val queued : t -> int
  (** Events pushed and not yet read. *)
end
