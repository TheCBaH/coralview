[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

(** Indexed hardware state, kept up to date incrementally: register files, scoreboards, tile and vector
    register files. A store is a persistent snapshot signal, so the state at any sample stays valid after
    later samples, and an event of the entries that changed in a sample. Stores come from storage the
    trace holds ({!mirror}, {!mirror_packed}) or from write events ({!replay}); {!relate} checks a relation
    between stores, rechecking only the keys that changed. *)

type 'v t
(** An immutable snapshot, by integer key. *)

val empty : 'v t
val of_list : (int * 'v) list -> 'v t
val get : 'v t -> int -> 'v option
val bindings : 'v t -> (int * 'v) list
val cardinal : 'v t -> int
val equal : ('v -> 'v -> bool) -> 'v t -> 'v t -> bool

val diff : ('v -> 'v -> bool) -> 'v t -> 'v t -> (int * 'v option * 'v option) list
(** The keys whose entries differ, ascending, with the entry in each. *)

type ('v, 'c) store = {
  state : ('v t, 'c) Frp.Sig.t;
  changes : ((int * 'v) list, 'c) Frp.Ev.t;
      (** Fires at each sample where entries changed, with their new values, ascending by key. A mirror
          fires at the first sample with every entry. *)
}

val keys : ('v, 'c) store -> (int list, 'c) Frp.Ev.t
(** The keys of {!changes}. *)

val mirror :
  ?purpose:string ->
  ?eq:('v -> 'v -> bool) ->
  'c Bind.scope ->
  (int * string) list ->
  'v Bind.decoder ->
  ('v, 'c) store
(** One signal of the scope per entry, keyed as given. [eq] (structural by default) decides whether a
    re-decoded entry changed. Raises {!Bind.Unbound}. *)

val mirror_fields :
  ?purpose:string ->
  ?eq:('v -> 'v -> bool) ->
  'c Bind.scope ->
  (int * (string * Bind.width_rule) list) list ->
  (Logic.t list -> 'v) ->
  ('v, 'c) store
(** Entries made of several signals each, such as a float register kept as sign, exponent and mantissa:
    [combine] gets an entry's fields in the order given whenever one of them changed. Raises
    {!Bind.Unbound}. *)

val mirror_packed :
  ?purpose:string ->
  ?first_key:int ->
  ?eq:('v -> 'v -> bool) ->
  'c Bind.scope ->
  string ->
  entries:int ->
  width:int ->
  (Bits.t -> 'v) ->
  ('v, 'c) store
(** A packed array [logic [entries-1:0][width-1:0]]: entry [i], keyed [first_key + i] (default 0), is
    bits [i*width] to [i*width+width-1].
    Raises {!Bind.Unbound} unless the signal is exactly [entries * width] bits. X/Z bits read as 0 and
    are reported. *)

val previous : 'c Frp.Clock.t -> ('v, 'c) store -> ('v, 'c) store
(** The store one sample earlier: the state of the previous sample, and the changes made in it. For
    storage that a write updates at the next clock edge. *)

val replay :
  ?eq:('v -> 'v -> bool) ->
  init:'v t ->
  ('v option -> 'w -> 'v) ->
  ((int * 'w) list, 'c) Frp.Ev.t ->
  ('v, 'c) store
(** The state written by events of [(key, write)] lists, applied in list order with [merge old write]:
    write ports, retirements. *)

val relate :
  ?severity:Frp.Diag.severity ->
  'c Frp.Clock.t ->
  Frp.Net.t ->
  source:string ->
  code:string ->
  keys:int list ->
  (int list, 'c) Frp.Ev.t list ->
  (int -> string option) ->
  unit
(** Checks [check key] for every key at the first sample, then for the keys of the given events at each
    sample, and reports a diagnostic when a key starts failing. [check] reads the stores it relates
    (with {!Frp.Sig.peek}); it must depend only on stores whose changes are among the events. *)
