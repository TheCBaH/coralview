[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Vcd_types

module D = struct
  type severity = Error | Warning | Info

  type t = {
    severity : severity;
    source : string;
    code : string;
    cycle : int option;
    time : Timestamp.t option;
    paths : Reference.t list;
    message : string;
  }
end

type ext = ..
type kind = K_signal | K_event | K_machine | K_delay | K_source | K_clock
type stats = { mutable evals : int; mutable changes : int }

type 'a node = {
  id : int;  (** creation order, which is a topological order: inputs exist before their readers *)
  name : string;
  kind : kind;
  rc : clock_rec;
  mutable value : 'a;
  mutable succs : packed list;
  mutable preds : int list;
  mutable lagged : int list;
      (** inputs read from an earlier sample or another domain: [pre], [resample] *)
  mutable eval : unit -> bool;  (** recompute; true when the value changed or the event fired *)
  mutable reset : unit -> unit;  (** events: back to None at the domain's next sample *)
  st : stats;
}

and packed = P : 'a node -> packed

and clock_rec = {
  net : net;
  index : int;
  cname : string;
  spec : Trace.domain_spec;
  mutable sources : (int * packed) list;
  mutable delays : (packed * (unit -> bool)) list;
      (** newest first, so [pre (pre s)] latches outside in *)
  mutable every : packed list;
  mutable subs : (unit -> unit) list;  (** newest first *)
  mutable finishers : (unit -> packed list) list;
  mutable cycle : int node option;
  mutable time : Timestamp.t node option;
  mutable enabled : bool node option;
}

and net = {
  mutable next_id : int;
  mutable nodes : packed list;
  mutable clocks : clock_rec list;
  mutable frozen : bool;
  mutable tick : Trace.tick;
  mutable sampler : Sampler.t option;
  mutable finishing : bool;  (** past the last sample: machines no longer step *)
  mutable diags : D.t list;
  mutable ndiags : int;
  mutable dropped : int;
  mutable exts : ext list;
  mutable checks : (unit -> string list) list;
}

type ('a, 'c) signal = 'a node
type ('a, 'c) event = 'a option node

let kind_name = function
  | K_signal -> "sig"
  | K_event -> "ev"
  | K_machine -> "machine"
  | K_delay -> "pre"
  | K_source -> "source"
  | K_clock -> "clock"

let check_open net = if net.frozen then invalid_arg "Frp: the net is already compiled"

let mk ?name ~kind rc value =
  let net = rc.net in
  check_open net;
  let id = net.next_id in
  net.next_id <- id + 1;
  let name = match name with Some n -> n | None -> Printf.sprintf "%s#%d" (kind_name kind) id in
  let n =
    {
      id;
      name;
      kind;
      rc;
      value;
      succs = [];
      preds = [];
      lagged = [];
      eval = (fun () -> false);
      reset = ignore;
      st = { evals = 0; changes = 0 };
    }
  in
  net.nodes <- P n :: net.nodes;
  n

let mk_event ?name rc =
  let n = mk ?name ~kind:K_event rc None in
  n.reset <- (fun () -> n.value <- None);
  n

let dep n a =
  if a.rc != n.rc then
    invalid_arg (Printf.sprintf "Frp: %s and %s are in different clock domains" a.name n.name);
  a.succs <- P n :: a.succs;
  n.preds <- a.id :: n.preds

let set_if eq n v =
  if eq v n.value then false
  else begin
    n.value <- v;
    true
  end

let fire n v =
  n.value <- Some v;
  true

module Net = struct
  type t = net

  let create () =
    {
      next_id = 0;
      nodes = [];
      clocks = [];
      frozen = false;
      tick = { Trace.domain = 0; index = 0; time = Timestamp.of_int64 0L; enabled = true };
      sampler = None;
      finishing = false;
      diags = [];
      ndiags = 0;
      dropped = 0;
      exts = [];
      checks = [];
    }

  let domains net = Array.of_list (List.rev_map (fun rc -> rc.spec) net.clocks)

  type nonrec ext = ext = ..

  let add_ext net e = net.exts <- e :: net.exts
  let exts net = net.exts

  let add_check net f =
    check_open net;
    net.checks <- f :: net.checks
end

module Clock = struct
  type 'c t = clock_rec
  type any = Any : 'c t -> any

  let define net ~name spec =
    check_open net;
    let rc =
      {
        net;
        index = List.length net.clocks;
        cname = name;
        spec;
        sources = [];
        delays = [];
        every = [];
        subs = [];
        finishers = [];
        cycle = None;
        time = None;
        enabled = None;
      }
    in
    net.clocks <- rc :: net.clocks;
    Any rc

  let name rc = rc.cname
end

module Sig = struct
  type ('a, 'c) t = ('a, 'c) signal

  let const rc x = mk ~kind:K_signal rc x

  let map ?name ?(eq = ( == )) f a =
    let n = mk ?name ~kind:K_signal a.rc (f a.value) in
    n.eval <- (fun () -> set_if eq n (f a.value));
    dep n a;
    n

  let map2 ?name ?(eq = ( == )) f a b =
    let n = mk ?name ~kind:K_signal a.rc (f a.value b.value) in
    n.eval <- (fun () -> set_if eq n (f a.value b.value));
    dep n a;
    dep n b;
    n

  let ( let+ ) a f = map f a
  let ( and+ ) a b = map2 ~eq:(fun (x, y) (x', y') -> x == x' && y == y') (fun x y -> (x, y)) a b

  let all = function
    | [] -> invalid_arg "Sig.all: empty list"
    | a :: _ as l ->
        let values () = List.map (fun s -> s.value) l in
        let n = mk ~kind:K_signal a.rc (values ()) in
        n.eval <- (fun () -> set_if (List.equal ( == )) n (values ()));
        List.iter (dep n) l;
        n

  let pre ~init a =
    let n = mk ~kind:K_delay a.rc init in
    n.lagged <- [ a.id ];
    a.rc.delays <- (P n, fun () -> set_if ( == ) n a.value) :: a.rc.delays;
    n

  let hold ~init e =
    let n = mk ~kind:K_signal e.rc init in
    n.eval <- (fun () -> match e.value with Some x -> set_if ( == ) n x | None -> false);
    dep n e;
    n

  let fold ?name ~init f e =
    let n = mk ?name ~kind:K_signal e.rc init in
    n.eval <-
      (fun () -> match e.value with Some x -> set_if ( == ) n (f n.value x) | None -> false);
    dep n e;
    n

  let changes ?(eq = ( == )) a =
    let n = mk_event a.rc in
    let prev = ref None in
    n.eval <-
      (fun () ->
        let v = a.value in
        match !prev with
        | Some p when eq p v -> false
        | Some _ ->
            prev := Some v;
            fire n v
        | None ->
            prev := Some v;
            false);
    dep n a;
    n

  let clock_node get set ~name ~kind rc init =
    match get rc with
    | Some n -> n
    | None ->
        let n = mk ~name:(rc.cname ^ "." ^ name) ~kind rc init in
        set rc n;
        n

  let cycle rc =
    clock_node
      (fun rc -> rc.cycle)
      (fun rc n -> rc.cycle <- Some n)
      ~name:"cycle" ~kind:K_clock rc 0

  let time rc =
    clock_node
      (fun rc -> rc.time)
      (fun rc n -> rc.time <- Some n)
      ~name:"time" ~kind:K_clock rc (Timestamp.of_int64 0L)

  let enabled rc =
    clock_node
      (fun rc -> rc.enabled)
      (fun rc n -> rc.enabled <- Some n)
      ~name:"enabled" ~kind:K_clock rc true

  let peek n = n.value
end

module Ev = struct
  type ('a, 'c) t = ('a, 'c) event

  let never rc = mk_event rc

  let on e f =
    let n = mk_event e.rc in
    n.eval <- (fun () -> match e.value with Some x -> f n x | None -> false);
    dep n e;
    n

  let map f e = on e (fun n x -> fire n (f x))
  let filter p e = on e (fun n x -> p x && fire n x)
  let filter_map f e = on e (fun n x -> match f x with Some y -> fire n y | None -> false)

  let when_ c s =
    let n = mk_event c.rc in
    n.eval <- (fun () -> c.value && fire n s.value);
    dep n c;
    dep n s;
    c.rc.every <- P n :: c.rc.every;
    n

  let edge ~from b =
    let n = mk_event b.rc in
    let prev = ref None in
    n.eval <-
      (fun () ->
        let v = b.value in
        let p = !prev in
        prev := Some v;
        p = Some from && v <> from && fire n ());
    dep n b;
    n

  let rising b = edge ~from:false b
  let falling b = edge ~from:true b

  let merge f a b =
    let n = mk_event a.rc in
    n.eval <-
      (fun () ->
        match (a.value, b.value) with
        | Some x, Some y -> fire n (f x y)
        | Some x, None | None, Some x -> fire n x
        | None, None -> false);
    dep n a;
    dep n b;
    n

  let union = function
    | [] -> invalid_arg "Ev.union: empty list"
    | e :: _ as l ->
        let n = mk_event e.rc in
        n.eval <-
          (fun () ->
            match List.filter_map (fun e -> e.value) l with [] -> false | xs -> fire n xs);
        List.iter (dep n) l;
        n

  let tag s e =
    let n = on e (fun n x -> fire n (x, s.value)) in
    dep n s;
    n

  let scan ~init f e =
    let st = ref init in
    on e (fun n x ->
        let s, o = f !st x in
        st := s;
        match o with Some y -> fire n y | None -> false)

  let flatten e = on e (fun n l -> l <> [] && fire n l)

  let gather = function
    | [] -> invalid_arg "Ev.gather: empty list"
    | s :: _ as l ->
        let n = mk_event s.rc in
        n.eval <-
          (fun () ->
            match List.filter_map (fun s -> s.value) l with [] -> false | xs -> fire n xs);
        List.iter (dep n) l;
        s.rc.every <- P n :: s.rc.every;
        n

  let subscribe e f =
    check_open e.rc.net;
    e.rc.subs <- (fun () -> match e.value with Some x -> f x | None -> ()) :: e.rc.subs
end

module Machine = struct
  type ('s, 'i, 'o) spec = {
    name : string;
    init : 's;
    step : tick:Trace.tick -> 's -> 'i -> 's * 'o list;
    finish : 's -> 'o list;
    every_tick : bool;
  }

  let run spec i =
    let st = mk ~name:spec.name ~kind:K_machine i.rc spec.init in
    let out = mk_event ~name:(spec.name ^ ".out") i.rc in
    let pending = ref [] in
    st.eval <-
      (fun () ->
        (not i.rc.net.finishing)
        &&
        let s, o = spec.step ~tick:i.rc.net.tick st.value i.value in
        pending := o;
        let changed = s != st.value in
        st.value <- s;
        changed || o <> []);
    out.eval <-
      (fun () ->
        match !pending with
        | [] -> false
        | l ->
            pending := [];
            fire out l);
    dep st i;
    dep out st;
    if spec.every_tick then i.rc.every <- P st :: i.rc.every;
    i.rc.finishers <-
      (fun () ->
        match spec.finish st.value with
        | [] -> []
        | l ->
            pending := l;
            [ P out ])
      :: i.rc.finishers;
    (out, st)
end

module Source = struct
  let make ?name ?(eq = ( == )) rc (s : Trace.signal) ~init read =
    let name = match name with Some n -> n | None -> Reference.to_string s.path in
    let n = mk ~name ~kind:K_source rc init in
    n.eval <-
      (fun () ->
        match rc.net.sampler with Some sm -> set_if eq n (read sm s.slot) | None -> false);
    rc.sources <- ((s.slot :> int), P n) :: rc.sources;
    n

  let logic ?name ?eq rc s ~init decode =
    make ?name ?eq rc s ~init (fun sm slot -> decode (Sampler.logic sm slot))

  let value ?name ?eq rc s ~init decode =
    make ?name ?eq rc s ~init (fun sm slot -> decode (Sampler.value sm slot))
end

module Clock_cross = struct
  let resample a rc =
    let n = mk ~kind:K_signal rc a.value in
    n.lagged <- [ a.id ];
    n.eval <- (fun () -> set_if ( == ) n a.value);
    rc.every <- P n :: rc.every;
    n
end

module Diag = struct
  type severity = D.severity = Error | Warning | Info

  type t = D.t = {
    severity : severity;
    source : string;
    code : string;
    cycle : int option;
    time : Timestamp.t option;
    paths : Reference.t list;
    message : string;
  }

  let max_diags = ref 10_000

  let make ?(severity = Warning) ?(paths = []) ~source ~code message =
    { severity; source; code; cycle = None; time = None; paths; message }

  let record net d =
    if net.ndiags >= !max_diags then net.dropped <- net.dropped + 1
    else begin
      let d =
        {
          d with
          cycle = (match d.cycle with Some _ -> d.cycle | None -> Some net.tick.index);
          time = (match d.time with Some _ -> d.time | None -> Some net.tick.time);
        }
      in
      net.diags <- d :: net.diags;
      net.ndiags <- net.ndiags + 1
    end

  let report = record

  let emit net e f =
    if e.rc.net != net then invalid_arg "Diag.emit: event of another net";
    Ev.subscribe e (fun x -> match f x with Some d -> record net d | None -> ())

  let stream net = List.to_seq (List.rev net.diags)
  let dropped net = net.dropped

  let pp ppf d =
    let sev = match d.severity with Error -> "error" | Warning -> "warning" | Info -> "info" in
    Format.fprintf ppf "%s[%s] %s" sev d.code d.source;
    Option.iter (Format.fprintf ppf " cycle %d") d.cycle;
    Option.iter (Format.fprintf ppf " time %a" Timestamp.pp) d.time;
    Format.fprintf ppf ": %s" d.message;
    List.iter (fun r -> Format.fprintf ppf "@ %s" (Reference.to_string r)) d.paths
end

module Heap = struct
  type t = { mutable a : int array; mutable n : int }

  let create () = { a = Array.make 64 0; n = 0 }
  let is_empty h = h.n = 0

  let push h x =
    if h.n = Array.length h.a then begin
      let b = Array.make (2 * h.n) 0 in
      Array.blit h.a 0 b 0 h.n;
      h.a <- b
    end;
    let i = ref h.n in
    h.n <- h.n + 1;
    while !i > 0 && h.a.((!i - 1) / 2) > x do
      h.a.(!i) <- h.a.((!i - 1) / 2);
      i := (!i - 1) / 2
    done;
    h.a.(!i) <- x

  let pop h =
    let top = h.a.(0) in
    h.n <- h.n - 1;
    let x = h.a.(h.n) in
    let i = ref 0 and go = ref true in
    while !go do
      let l = (2 * !i) + 1 in
      if l >= h.n then go := false
      else begin
        let c = if l + 1 < h.n && h.a.(l + 1) < h.a.(l) then l + 1 else l in
        if h.a.(c) < x then begin
          h.a.(!i) <- h.a.(c);
          i := c
        end
        else go := false
      end
    done;
    h.a.(!i) <- x;
    top
end

module Sched = struct
  type node_stats = { evals : int; changes : int }
  type build_error = Unbound_source of string | Check_failed of string
  type strategy = Incremental | Sweep

  type run_stats = {
    ticks : int array;
    node_evals : int;
    wall_s : float;
    per_node : (string * node_stats) list;
  }

  type t = {
    net : net;
    strategy : strategy;
    clocks : clock_rec array;
    nodes : packed array;  (** by id *)
    by_domain : packed array array;  (** by id *)
    sources : (int, packed list) Hashtbl.t array;
    subs : (unit -> unit) array array;
    heap : Heap.t;
    queued : Bitset.t;
    changed : Bitset.t;  (** [Sweep]: the nodes changed in the current sample *)
    fired : (unit -> unit) list array;
    last : Trace.tick option array;
  }

  let compile ?(strategy = Incremental) net =
    match List.concat_map (fun f -> f ()) (List.rev net.checks) with
    | _ :: _ as errors -> Error (List.map (fun e -> Check_failed e) errors)
    | [] ->
        net.frozen <- true;
        let nodes = Array.of_list (List.rev net.nodes) in
        let clocks = Array.of_list (List.rev net.clocks) in
        let nd = Array.length clocks in
        let by_domain = Array.make nd [] in
        Array.iter
          (function P n as p -> by_domain.(n.rc.index) <- p :: by_domain.(n.rc.index))
          nodes;
        let sources =
          Array.map
            (fun (rc : clock_rec) ->
              let h = Hashtbl.create 64 in
              List.iter
                (fun (slot, p) ->
                  Hashtbl.replace h slot (p :: Option.value (Hashtbl.find_opt h slot) ~default:[]))
                rc.sources;
              h)
            clocks
        in
        Ok
          {
            net;
            strategy;
            clocks;
            nodes;
            by_domain = Array.map (fun l -> Array.of_list (List.rev l)) by_domain;
            sources;
            subs = Array.map (fun (rc : clock_rec) -> Array.of_list (List.rev rc.subs)) clocks;
            heap = Heap.create ();
            queued = Bitset.create (Array.length nodes);
            changed = Bitset.create (Array.length nodes);
            fired = Array.make nd [];
            last = Array.make nd None;
          }

  let push t (P n) =
    if not (Bitset.mem t.queued n.id) then begin
      Bitset.add t.queued n.id;
      if t.strategy = Incremental then Heap.push t.heap n.id
    end

  (* A delay that latched or a clock node, which change outside evaluation. *)
  let mark_changed t (P n) =
    match t.strategy with
    | Incremental -> List.iter (push t) n.succs
    | Sweep -> Bitset.add t.changed n.id

  let eval t d n =
    n.st.evals <- n.st.evals + 1;
    n.eval ()
    && begin
      n.st.changes <- n.st.changes + 1;
      if n.kind = K_event then t.fired.(d) <- n.reset :: t.fired.(d);
      true
    end

  let drain t d =
    while not (Heap.is_empty t.heap) do
      let id = Heap.pop t.heap in
      Bitset.remove t.queued id;
      match t.nodes.(id) with P n -> if eval t d n then List.iter (push t) n.succs
    done

  (* The reference for [drain]: no heap and no successor lists. *)
  let sweep t d =
    Array.iter
      (function
        | P n ->
            if Bitset.mem t.queued n.id || List.exists (Bitset.mem t.changed) n.preds then
              if eval t d n then Bitset.add t.changed n.id)
      t.by_domain.(d);
    Bitset.clear t.queued;
    Bitset.clear t.changed

  let settle t d = match t.strategy with Incremental -> drain t d | Sweep -> sweep t d

  let clear_fired t d =
    List.iter (fun f -> f ()) t.fired.(d);
    t.fired.(d) <- []

  let step t sampler (tick : Trace.tick) =
    let d = tick.domain in
    let rc = t.clocks.(d) in
    t.net.tick <- tick;
    t.last.(d) <- Some tick;
    clear_fired t d;
    if tick.index > 0 then List.iter (fun (p, latch) -> if latch () then mark_changed t p) rc.delays;
    Option.iter
      (fun n ->
        n.value <- tick.index;
        mark_changed t (P n))
      rc.cycle;
    Option.iter (fun n -> if set_if Timestamp.equal n tick.time then mark_changed t (P n)) rc.time;
    Option.iter (fun n -> if set_if Bool.equal n tick.enabled then mark_changed t (P n)) rc.enabled;
    if tick.index = 0 then Array.iter (push t) t.by_domain.(d)
    else
      Bitset.iter
        (fun slot ->
          match Hashtbl.find_opt t.sources.(d) slot with
          | Some l -> List.iter (push t) l
          | None -> ())
        (Sampler.changed sampler);
    List.iter (push t) rc.every;
    settle t d;
    Array.iter (fun f -> f ()) t.subs.(d)

  let finish t =
    t.net.finishing <- true;
    Array.iteri
      (fun d rc ->
        match List.concat_map (fun f -> f ()) (List.rev rc.finishers) with
        | [] -> ()
        | outs ->
            Option.iter (fun tk -> t.net.tick <- tk) t.last.(d);
            clear_fired t d;
            List.iter (push t) outs;
            settle t d;
            Array.iter (fun f -> f ()) t.subs.(d))
      t.clocks

  let run t sampler =
    t.net.sampler <- Some sampler;
    let t0 = Unix.gettimeofday () in
    let ticks = Array.make (Array.length t.clocks) 0 in
    let rec loop () =
      match Sampler.next sampler with
      | None -> ()
      | Some tick ->
          step t sampler tick;
          ticks.(tick.domain) <- ticks.(tick.domain) + 1;
          loop ()
    in
    loop ();
    finish t;
    let per_node =
      Array.to_list
        (Array.map
           (function P n -> (n.name, { evals = n.st.evals; changes = n.st.changes }))
           t.nodes)
    in
    {
      ticks;
      node_evals = List.fold_left (fun a (_, (s : node_stats)) -> a + s.evals) 0 per_node;
      wall_s = Unix.gettimeofday () -. t0;
      per_node;
    }

  let dump_dot t oc =
    let shape = function
      | K_event -> "diamond"
      | K_machine -> "box3d"
      | K_delay -> "box"
      | K_source | K_clock -> "invhouse"
      | K_signal -> "ellipse"
    in
    Printf.fprintf oc "digraph hwfrp {\n";
    Array.iter
      (function
        | P n -> Printf.fprintf oc "  n%d [label=%S shape=%s];\n" n.id n.name (shape n.kind))
      t.nodes;
    Array.iter
      (function
        | P n ->
            let edge style p = Printf.fprintf oc "  n%d -> n%d%s;\n" p n.id style in
            List.iter (edge "") (List.rev n.preds);
            List.iter (edge " [style=dashed]") n.lagged)
      t.nodes;
    Printf.fprintf oc "}\n"
end
