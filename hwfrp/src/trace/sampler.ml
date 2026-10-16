[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Vcd_types

type domain = {
  spec : Trace.domain_spec;
  mutable index : int;
  pending : Bitset.t;  (** slots changed since this domain's last sample *)
  last : Value.t array;  (** values at this domain's last sample *)
  changed : Bitset.t;
}

type action = Tick of int * Timestamp.t | Apply of (int * Value.t) list
type stats = { events : int; changes_seen : int; changes_tracked : int; timestamps : int }

type t = {
  slot_of_id : (string, int) Hashtbl.t;
  values : Value.t array;
  widths : int array;
  logic_cache : Logic.t option array;
  domains : domain array;
  mutable events : Vcd_ast.event Seq.t;
  mutable batch : (int * Value.t) list;  (** reversed *)
  mutable batch_time : Timestamp.t;
  mutable queue : action list;
  mutable current : int;
  mutable finished : bool;
  mutable n_events : int;
  mutable n_seen : int;
  mutable n_tracked : int;
  mutable n_timestamps : int;
}

let unset = Value.Scalar Value.X

let create trace specs =
  Trace.freeze trace;
  let signals = Trace.tracked trace in
  let n = Array.length signals in
  let slot_of_id = Hashtbl.create (2 * n) in
  Array.iter
    (fun (s : Trace.signal) -> Hashtbl.replace slot_of_id (ID.to_string s.id) (s.slot :> int))
    signals;
  {
    slot_of_id;
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
          })
        specs;
    events = Trace.events trace;
    batch = [];
    batch_time = Timestamp.of_int64 0L;
    queue = [];
    current = 0;
    finished = false;
    n_events = 0;
    n_seen = 0;
    n_tracked = 0;
    n_timestamps = 0;
  }

let level : Value.t -> bool option = function
  | Scalar (B0 | L) | Int 0 -> Some false
  | Scalar (B1 | H) | Int 1 -> Some true
  | _ -> None

let edge t batch (spec : Trace.domain_spec) =
  let clk = (spec.clock :> int) in
  let rec last = function [] -> None | (s, v) :: rest -> if s = clk then Some v else last rest in
  match last batch with
  | None -> `None
  | Some v -> (
      match (level t.values.(clk), level v) with
      | Some false, Some true -> `Rising
      | Some true, Some false -> `Falling
      | _ -> `None)

(* [t.batch] holds the changes of [t.batch_time]; schedule its samples around applying it. *)
let close_batch t =
  let batch = t.batch in
  t.batch <- [];
  if batch <> [] then begin
    let pre = ref [] and post = ref [] in
    Array.iteri
      (fun d dom ->
        match (dom.spec.rule, edge t batch dom.spec) with
        | Before_rising, `Rising -> pre := Tick (d, t.batch_time) :: !pre
        | After_rising, `Rising | After_falling, `Falling -> post := Tick (d, t.batch_time) :: !post
        | _ -> ())
      t.domains;
    t.queue <- List.rev_append !pre (Apply (List.rev batch) :: List.rev !post)
  end

let rec pull t =
  match t.events () with
  | Seq.Nil ->
      t.finished <- true;
      close_batch t
  | Seq.Cons (ev, rest) -> (
      t.events <- rest;
      t.n_events <- t.n_events + 1;
      match ev with
      | Vcd_ast.Timestamp ts ->
          t.n_timestamps <- t.n_timestamps + 1;
          close_batch t;
          t.batch_time <- ts;
          if t.queue = [] then pull t
      | Change (id, v) ->
          t.n_seen <- t.n_seen + 1;
          (match Hashtbl.find_opt t.slot_of_id (ID.to_string id) with
          | Some s ->
              t.n_tracked <- t.n_tracked + 1;
              t.batch <- (s, v) :: t.batch
          | None -> ());
          pull t
      | DumpStart _ | DumpEnd | SimComment _ -> pull t)

let apply t batch =
  List.iter
    (fun (s, v) ->
      if t.values.(s) <> v then begin
        t.values.(s) <- v;
        t.logic_cache.(s) <- None;
        Array.iter (fun d -> Bitset.add d.pending s) t.domains
      end)
    batch

let emit t d time =
  let dom = t.domains.(d) in
  Bitset.clear dom.changed;
  Bitset.iter
    (fun s ->
      if dom.last.(s) <> t.values.(s) then begin
        dom.last.(s) <- t.values.(s);
        Bitset.add dom.changed s
      end)
    dom.pending;
  Bitset.clear dom.pending;
  let enabled =
    match dom.spec.enable with None -> true | Some e -> level t.values.((e :> int)) = Some true
  in
  let tick = { Trace.domain = d; index = dom.index; time; enabled } in
  dom.index <- dom.index + 1;
  t.current <- d;
  tick

let rec next t =
  match t.queue with
  | Tick (d, time) :: rest ->
      t.queue <- rest;
      Some (emit t d time)
  | Apply b :: rest ->
      t.queue <- rest;
      apply t b;
      next t
  | [] ->
      if t.finished then None
      else begin
        pull t;
        next t
      end

let value t s = t.values.((s : Trace.slot :> int))

let logic t s =
  let s = (s : Trace.slot :> int) in
  match t.logic_cache.(s) with
  | Some l -> l
  | None ->
      let l =
        match Logic.of_value ~width:t.widths.(s) t.values.(s) with
        | Ok l -> l
        | Error _ -> Logic.unknown t.widths.(s)
      in
      t.logic_cache.(s) <- Some l;
      l

let changed t = t.domains.(t.current).changed

let stats t =
  {
    events = t.n_events;
    changes_seen = t.n_seen;
    changes_tracked = t.n_tracked;
    timestamps = t.n_timestamps;
  }
