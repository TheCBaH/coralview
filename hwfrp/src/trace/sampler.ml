[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Vcd_types

module SH = Hashtbl.Make (struct
  type t = string

  let equal = String.equal
  let hash = Hashtbl.hash
end)

type domain = {
  spec : Trace.domain_spec;
  mutable index : int;
  pending : Bitset.t;  (** slots changed since this domain's last sample *)
  last : Value.t array;  (** values at this domain's last sample *)
  changed : Bitset.t;
  mutable clock_seen : bool;  (** the clock changed in the open batch *)
  mutable clock_new : Value.t;  (** and this is its last value there *)
}

type action = Action_tick of int * Timestamp.t | Apply of (int * Value.t) list
type activity = { signal : Trace.signal; changes : int; unknown_at_end : bool }
type stats = { events : int; changes_seen : int; changes_tracked : int; timestamps : int }

type t = {
  slot_of_id : int SH.t;
  clock_of : int list array;  (** by slot: the domains it clocks *)
  values : Value.t array;
  widths : int array;
  logic_cache : (Logic.t, Logic.decode_error) result option array;
  domains : domain array;
  events : unit -> Trace.pull;
  mutable batch : (int * Value.t) list;  (** reversed *)
  mutable batch_time : Timestamp.t;
  mutable queue : action list;
  mutable current : int;
  mutable finished : bool;
  mutable n_events : int;
  mutable n_seen : int;
  mutable n_tracked : int;
  mutable n_timestamps : int;
  signals : Trace.signal array;
  n_changed : int array;
}

let unset = Value.Scalar Value.X

(* Structural equality, with the common cases off the polymorphic comparison. *)
let same (a : Value.t) (b : Value.t) =
  match (a, b) with
  | Int x, Int y -> x = y
  | Scalar x, Scalar y -> x = y
  | Int64 x, Int64 y -> Int64.equal x y
  | Bytes x, Bytes y -> Bytes.equal x y
  | _ -> a = b

let create trace specs =
  Trace.freeze trace;
  let signals = Trace.tracked trace in
  let n = Array.length signals in
  let slot_of_id = SH.create (2 * n) in
  Array.iter
    (fun (s : Trace.signal) -> SH.replace slot_of_id (ID.to_string s.id) (s.slot :> int))
    signals;
  let clock_of = Array.make n [] in
  Array.iteri
    (fun d (spec : Trace.domain_spec) ->
      let c = (spec.clock :> int) in
      if c >= 0 && c < n then clock_of.(c) <- d :: clock_of.(c))
    specs;
  {
    slot_of_id;
    clock_of;
    values = Array.make n unset;
    widths = Array.map (fun (s : Trace.signal) -> s.width) signals;
    logic_cache = Array.make n None;
    domains =
      Array.map
        (fun spec ->
          {
            spec;
            index = 0;
            pending = Bitset.create n;
            last = Array.make n unset;
            changed = Bitset.create n;
            clock_seen = false;
            clock_new = unset;
          })
        specs;
    events = Trace.pull trace;
    batch = [];
    batch_time = Timestamp.of_int64 0L;
    queue = [];
    current = 0;
    finished = false;
    n_events = 0;
    n_seen = 0;
    n_tracked = 0;
    n_timestamps = 0;
    signals;
    n_changed = Array.make n 0;
  }

let level : Value.t -> bool option = function
  | Scalar (B0 | L) | Int 0 -> Some false
  | Scalar (B1 | H) | Int 1 -> Some true
  | _ -> None

let edge t (dom : domain) =
  if not dom.clock_seen then `None
  else
    match (level t.values.((dom.spec.clock :> int)), level dom.clock_new) with
    | Some false, Some true -> `Rising
    | Some true, Some false -> `Falling
    | _ -> `None

(* [t.batch] holds the changes of [t.batch_time]; schedule its samples around applying it. *)
let close_batch t =
  let batch = t.batch in
  t.batch <- [];
  match batch with
  | [] -> ()
  | _ ->
      let pre = ref [] and post = ref [] in
      Array.iteri
        (fun d dom ->
          (match (dom.spec.rule, edge t dom) with
          | Before_rising, `Rising -> pre := Action_tick (d, t.batch_time) :: !pre
          | After_rising, `Rising | After_falling, `Falling ->
              post := Action_tick (d, t.batch_time) :: !post
          | _ -> ());
          dom.clock_seen <- false)
        t.domains;
      t.queue <- List.rev_append !pre (Apply (List.rev batch) :: List.rev !post)

let rec mark_clock t v = function
  | [] -> ()
  | d :: rest ->
      let dom = t.domains.(d) in
      dom.clock_seen <- true;
      dom.clock_new <- v;
      mark_clock t v rest

(* [`More]: the queue may hold samples, or the source ended; [`Starved]: nothing until it has more. *)
let rec pull t =
  match t.events () with
  | Trace.Ended ->
      t.finished <- true;
      close_batch t;
      `More
  | Starved -> `Starved
  | Event ev -> (
      t.n_events <- t.n_events + 1;
      match ev with
      | Vcd_ast.Timestamp ts ->
          t.n_timestamps <- t.n_timestamps + 1;
          close_batch t;
          t.batch_time <- ts;
          if t.queue == [] then pull t else `More
      | Change (id, v) ->
          t.n_seen <- t.n_seen + 1;
          (match SH.find_opt t.slot_of_id (ID.to_string id) with
          | Some s ->
              t.n_tracked <- t.n_tracked + 1;
              t.batch <- (s, v) :: t.batch;
              mark_clock t v t.clock_of.(s)
          | None -> ());
          pull t
      | DumpStart _ | DumpEnd | SimComment _ -> pull t)

let apply t batch =
  List.iter
    (fun (s, v) ->
      if not (same t.values.(s) v) then begin
        t.values.(s) <- v;
        t.n_changed.(s) <- t.n_changed.(s) + 1;
        t.logic_cache.(s) <- None;
        for d = 0 to Array.length t.domains - 1 do
          Bitset.add t.domains.(d).pending s
        done
      end)
    batch

let emit t d time =
  let dom = t.domains.(d) in
  Bitset.clear dom.changed;
  Bitset.iter
    (fun s ->
      if not (same dom.last.(s) t.values.(s)) then begin
        dom.last.(s) <- t.values.(s);
        Bitset.add dom.changed s
      end)
    dom.pending;
  Bitset.clear dom.pending;
  let enabled =
    match dom.spec.enable with None -> true | Some e -> level t.values.((e :> int)) = Some true
  in
  let in_reset =
    match dom.spec.reset with
    | None -> false
    | Some r -> level t.values.((r.signal :> int)) <> Some (not r.active)
  in
  let tick = { Trace.domain = d; index = dom.index; time; enabled; in_reset } in
  dom.index <- dom.index + 1;
  t.current <- d;
  tick

type poll = Tick of Trace.tick | Starved | Ended

let rec poll t =
  match t.queue with
  | Action_tick (d, time) :: rest ->
      t.queue <- rest;
      Tick (emit t d time)
  | Apply b :: rest ->
      t.queue <- rest;
      apply t b;
      poll t
  | [] -> ( if t.finished then Ended else match pull t with `More -> poll t | `Starved -> Starved)

let next t =
  match poll t with
  | Tick tick -> Some tick
  | Ended -> None
  | Starved -> invalid_arg "Sampler.next: the source is starved; use Sampler.poll"

let value t s = t.values.((s : Trace.slot :> int))

let decoded t s =
  let s = (s : Trace.slot :> int) in
  match t.logic_cache.(s) with
  | Some r -> r
  | None ->
      let r = Logic.of_value ~width:t.widths.(s) t.values.(s) in
      t.logic_cache.(s) <- Some r;
      r

let logic t s =
  match decoded t s with Ok l -> l | Error _ -> Logic.unknown t.widths.((s : Trace.slot :> int))

let activity t =
  Array.mapi
    (fun i signal ->
      {
        signal;
        changes = t.n_changed.(i);
        unknown_at_end = Logic.to_known (logic t signal.Trace.slot) = None;
      })
    t.signals

let changed t = t.domains.(t.current).changed

let stats t =
  {
    events = t.n_events;
    changes_seen = t.n_seen;
    changes_tracked = t.n_tracked;
    timestamps = t.n_timestamps;
  }
