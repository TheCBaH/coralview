[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

let name = "axi"

let doc =
  "External traffic: transactions on the core's AXI master port, with size, address, timing and \
   throughput, each pinned to the request and instruction that made it."

let needs = "axi_master" :: Commits.needs

let resp_name = function
  | 0 -> "OKAY"
  | 1 -> "EXOKAY"
  | 2 -> "SLVERR"
  | 3 -> "DECERR"
  | r -> string_of_int r

module IM = Map.Make (Int)

module PM = Map.Make (struct
  type t = int * int

  let compare (a, b) (c, d) = match Int.compare a c with 0 -> Int.compare b d | n -> n
end)

module SM = Map.Make (struct
  type t = int * string

  let compare = compare
end)

module Config = struct
  type t = { region : Region.t }

  let default = { region = Region.none }
end

module Origin = struct
  type t = {
    issued : int;
    request : int;
    write : bool option;
    agrees : bool;
    instance : Instance.t option;
  }

  let jsont =
    Jsont.Object.map ~kind:"origin" (fun issued request write agrees instance ->
        { issued; request; write; agrees; instance })
    |> Jsont.Object.mem "issued" Jsont.int ~enc:(fun o -> o.issued)
    |> Jsont.Object.mem "request" Jsont.int ~enc:(fun o -> o.request)
    |> Codec.opt (fun o -> o.write) "write" Jsont.bool
    |> Jsont.Object.mem "agrees" Jsont.bool ~enc:(fun o -> o.agrees)
    |> Codec.opt (fun o -> o.instance) "instance" Instance.jsont
    |> Jsont.Object.finish
end

module Event = struct
  type transaction = {
    txn : Transaction.t;
    source : string option;
    region : string option;
    origin : Origin.t option;
    burst : int;
    beat_bytes : int;
  }

  type unmatched = { cycle : int; write : bool; id : int; what : string }
  type t = Transaction of transaction | Unmatched of unmatched

  let transaction =
    Codec.case "axi.transaction"
      (fun t -> Transaction t)
      (Jsont.Object.map (fun txn source region origin burst beat_bytes ->
           { txn; source; region; origin; burst; beat_bytes })
      |> Jsont.Object.mem "transaction" Codec.transaction ~enc:(fun t -> t.txn)
      |> Codec.opt (fun t -> t.source) "source" Jsont.string
      |> Codec.opt (fun t -> t.region) "region" Jsont.string
      |> Codec.opt (fun t -> t.origin) "origin" Origin.jsont
      |> Jsont.Object.mem "burst" Jsont.int ~enc:(fun t -> t.burst)
      |> Jsont.Object.mem "beat_bytes" Jsont.int ~enc:(fun t -> t.beat_bytes)
      |> Jsont.Object.finish)

  let unmatched =
    Codec.case "axi.unmatched"
      (fun u -> Unmatched u)
      (Jsont.Object.map (fun cycle write id what -> { cycle; write; id; what })
      |> Jsont.Object.mem "cycle" Jsont.int ~enc:(fun u -> u.cycle)
      |> Jsont.Object.mem "write" Jsont.bool ~enc:(fun u -> u.write)
      |> Jsont.Object.mem "id" Jsont.int ~enc:(fun u -> u.id)
      |> Jsont.Object.mem "what" Jsont.string ~enc:(fun u -> u.what)
      |> Jsont.Object.finish)

  let jsont =
    Codec.cases "axi.event"
      (function
        | Transaction t -> Jsont.Object.Case.value transaction t
        | Unmatched u -> Jsont.Object.Case.value unmatched u)
      Jsont.Object.Case.[ make transaction; make unmatched ]

  let cycle = function Transaction t -> t.txn.accepted | Unmatched u -> u.cycle

  let pc = function
    | Transaction { origin = Some { instance = Some i; _ }; _ } -> Some i.pc
    | _ -> None
end

let start (t : Event.transaction) =
  match t.origin with Some o -> min o.issued t.txn.requested | None -> t.txn.requested

let span (t : Event.transaction) = Option.map (fun c -> c - start t + 1) t.txn.completed

let throughput (t : Event.transaction) =
  Option.map (fun s -> float_of_int t.txn.bytes /. float_of_int s) (span t)

module Summary = struct
  type source = {
    id : int;
    source : string;
    transactions : int;
    bytes : int;
    pinned : int;
    instances : int;
    disagreeing : int;
  }

  type t = {
    cycles : int;
    reads : int;
    read_bytes : int;
    writes : int;
    write_bytes : int;
    unmatched : int;
    read_latency : Reduce.Stats.t;
    write_latency : Reduce.Stats.t;
    incomplete : int;
    first : int option;
    last : int option;
    occupancy : int list;
    max_reads : int;
    max_writes : int;
    sources : source list;
    resyncs : int;
    words : (int * int) list;
  }

  let source =
    Jsont.Object.map ~kind:"source"
      (fun id source transactions bytes pinned instances disagreeing ->
        { id; source; transactions; bytes; pinned; instances; disagreeing })
    |> Jsont.Object.mem "id" Jsont.int ~enc:(fun s -> s.id)
    |> Jsont.Object.mem "source" Jsont.string ~enc:(fun s -> s.source)
    |> Jsont.Object.mem "transactions" Jsont.int ~enc:(fun s -> s.transactions)
    |> Jsont.Object.mem "bytes" Jsont.int ~enc:(fun s -> s.bytes)
    |> Jsont.Object.mem "pinned" Jsont.int ~enc:(fun s -> s.pinned)
    |> Jsont.Object.mem "instances" Jsont.int ~enc:(fun s -> s.instances)
    |> Jsont.Object.mem "disagreeing" Jsont.int ~enc:(fun s -> s.disagreeing)
    |> Jsont.Object.finish

  let word =
    Jsont.Object.map ~kind:"word" (fun pc word -> (pc, word))
    |> Jsont.Object.mem "pc" Jsont.int ~enc:fst
    |> Jsont.Object.mem "word" Jsont.int ~enc:snd
    |> Jsont.Object.finish

  let jsont =
    Codec.record "axi.summary"
      (fun
        cycles
        reads
        read_bytes
        writes
        write_bytes
        unmatched
        read_latency
        write_latency
        incomplete
        first
        last
        occupancy
        max_reads
        max_writes
        sources
        resyncs
        words
      ->
        {
          cycles;
          reads;
          read_bytes;
          writes;
          write_bytes;
          unmatched;
          read_latency;
          write_latency;
          incomplete;
          first;
          last;
          occupancy;
          max_reads;
          max_writes;
          sources;
          resyncs;
          words;
        })
    |> Jsont.Object.mem "cycles" Jsont.int ~enc:(fun s -> s.cycles)
    |> Jsont.Object.mem "reads" Jsont.int ~enc:(fun s -> s.reads)
    |> Jsont.Object.mem "read_bytes" Jsont.int ~enc:(fun s -> s.read_bytes)
    |> Jsont.Object.mem "writes" Jsont.int ~enc:(fun s -> s.writes)
    |> Jsont.Object.mem "write_bytes" Jsont.int ~enc:(fun s -> s.write_bytes)
    |> Jsont.Object.mem "unmatched" Jsont.int ~enc:(fun s -> s.unmatched)
    |> Jsont.Object.mem "read_latency" Codec.stats ~enc:(fun s -> s.read_latency)
    |> Jsont.Object.mem "write_latency" Codec.stats ~enc:(fun s -> s.write_latency)
    |> Jsont.Object.mem "incomplete" Jsont.int ~enc:(fun s -> s.incomplete)
    |> Codec.opt (fun s -> s.first) "first" Jsont.int
    |> Codec.opt (fun s -> s.last) "last" Jsont.int
    |> Jsont.Object.mem "occupancy" Jsont.(list int) ~enc:(fun s -> s.occupancy)
    |> Jsont.Object.mem "max_reads" Jsont.int ~enc:(fun s -> s.max_reads)
    |> Jsont.Object.mem "max_writes" Jsont.int ~enc:(fun s -> s.max_writes)
    |> Jsont.Object.mem "sources" (Jsont.list source) ~enc:(fun s -> s.sources)
    |> Jsont.Object.mem "resyncs" Jsont.int ~enc:(fun s -> s.resyncs)
    |> Jsont.Object.mem "words" (Jsont.list word) ~enc:(fun s -> s.words)
    |> Jsont.Object.finish
end

(* The originator's request at the address handshake. *)
type pin = {
  issued : int;
  pc : int option;
  dispatched : int option;
  started : int option;
  o_addr : int;
  o_write : bool option;
  agrees : bool;
}

(* An accepted transaction, until it is emitted. *)
type pending = { txn : Transaction.t; x : Axi4.extra; pin : pin option; complete : bool }

type totals = {
  t_reads : int;
  t_read_bytes : int;
  t_writes : int;
  t_write_bytes : int;
  t_unmatched : int;
  t_rlat : Reduce.Stats.t;
  t_wlat : Reduce.Stats.t;
  t_incomplete : int;
  t_first : int;
  t_last : int;
  t_sources : (int * int * int * int * int) SM.t;
  t_pcs : unit IM.t;
}

type state = {
  axi : Axi4.state;
  waiting : (int * int) list IM.t;  (** Per source: dispatched PCs and cycles, oldest first. *)
  recent : (int * int option * int) list IM.t;  (** Per source: operations issued lately. *)
  resyncs : int;
  began : ((int * bool option * int option) * int) IM.t;  (** Per source: the request and since. *)
  retirement : int PM.t;  (** By PC and dispatch cycle. *)
  words : int IM.t;  (** By PC. *)
  outbox : pending IM.t;  (** By acceptance order. *)
  live : int;  (** Outstanding before this cycle. *)
  occupancy : int IM.t;
  zeros : int;  (** Cycles with none outstanding since the last with some, not yet counted. *)
  seen : bool;
  last_cycle : int;
  totals : totals;
}

let account ~cycles tot (t : Event.transaction) =
  let tx = t.txn in
  let lat stats = Option.fold ~none:stats ~some:(Reduce.Stats.add stats) (Transaction.latency tx) in
  let tot =
    if tx.write then
      {
        tot with
        t_writes = tot.t_writes + 1;
        t_write_bytes = tot.t_write_bytes + tx.bytes;
        t_wlat = lat tot.t_wlat;
      }
    else
      {
        tot with
        t_reads = tot.t_reads + 1;
        t_read_bytes = tot.t_read_bytes + tx.bytes;
        t_rlat = lat tot.t_rlat;
      }
  in
  let count f = match t.origin with Some o when f o -> 1 | _ -> 0 in
  let key = (tx.id, Option.value t.source ~default:"?") in
  let n, b, pinned, instance, disagree =
    Option.value (SM.find_opt key tot.t_sources) ~default:(0, 0, 0, 0, 0)
  in
  let instance' (o : Origin.t) =
    match o.instance with Some i -> i.dispatched <> None | None -> false
  in
  {
    tot with
    t_incomplete = (tot.t_incomplete + if tx.completed = None then 1 else 0);
    t_first = min tot.t_first (start t);
    t_last = max tot.t_last (Option.value tx.completed ~default:(cycles - 1));
    t_sources =
      SM.add key
        ( n + 1,
          b + tx.bytes,
          pinned + count (fun _ -> true),
          instance + count instance',
          disagree + count (fun (o : Origin.t) -> not o.agrees) )
        tot.t_sources;
    t_pcs =
      (match Event.pc (Transaction t) with Some pc -> IM.add pc () tot.t_pcs | None -> tot.t_pcs);
  }

let origin_of (t : Transaction.t) origins s cycle =
  match List.assoc_opt t.id origins with
  | Some (align, true, _, ((addr, w, pc) as req)) ->
      let issued =
        match IM.find_opt t.id s.began with Some (r, at) when r = req -> at | _ -> cycle
      in
      let agrees =
        addr land lnot (align - 1) = t.address && Option.fold ~none:true ~some:(( = ) t.write) w
      in
      let dispatched, started =
        match (pc, IM.find_opt t.id s.recent) with
        | Some pc, Some recent -> (
            match List.find_opt (fun (p, _, at) -> p = pc && at <= issued) recent with
            | Some (_, d, at) -> (d, Some at)
            | None -> (None, None))
        | _ -> (None, None)
      in
      Some { issued; pc; dispatched; started; o_addr = addr; o_write = w; agrees }
  | _ -> None

let event ~source ~region s p =
  let instance pin pc =
    {
      Instance.pc;
      word = IM.find_opt pc s.words;
      dispatched = pin.dispatched;
      issued = pin.started;
      retired = Option.bind pin.dispatched (fun d -> PM.find_opt (pc, d) s.retirement);
    }
  in
  {
    Event.txn = p.txn;
    source = source p.txn.id;
    region = Region.find region p.txn.address;
    origin =
      Option.map
        (fun pin ->
          {
            Origin.issued = pin.issued;
            request = pin.o_addr;
            write = pin.o_write;
            agrees = pin.agrees;
            instance = Option.map (instance pin) pin.pc;
          })
        p.pin;
    burst = p.x.burst;
    beat_bytes = p.x.beat_bytes;
  }

(* Issue first: an operation cannot leave the queue in the cycle it enters. A PC at the head that does
   not issue never will (a flush, or an operation with no requests): skip it. *)
let ops_step s cycle queues =
  List.fold_left
    (fun s (id, (enq, iss)) ->
      let q = Option.value (IM.find_opt id s.waiting) ~default:[] in
      let recent = Option.value (IM.find_opt id s.recent) ~default:[] in
      let q, recent, resyncs =
        List.fold_left
          (fun (q, recent, resyncs) pc ->
            let rec take n = function
              | (p, d) :: rest when p = pc -> (Some d, rest, n)
              | _ :: rest -> take (n + 1) rest
              | [] -> (None, [], n)
            in
            let d, q, resyncs = take resyncs q in
            (q, (pc, d, cycle) :: List.filteri (fun i _ -> i < 15) recent, resyncs))
          (q, recent, s.resyncs) iss
      in
      let q = q @ List.map (fun pc -> (pc, cycle)) enq in
      { s with waiting = IM.add id q s.waiting; recent = IM.add id recent s.recent; resyncs })
    s queues

let retire s = function
  | None -> s
  | Some commits ->
      List.fold_left
        (fun s (k : Commits.commit) ->
          {
            s with
            words = (match k.word with Some w -> IM.add k.pc w s.words | None -> s.words);
            retirement =
              (match k.dispatched with
              | Some d -> PM.add (k.pc, d) k.retired s.retirement
              | None -> s.retirement);
          })
        s commits

let ready s p =
  p.complete
  &&
  match p.pin with
  | Some { pc = Some pc; dispatched = Some d; _ } -> PM.mem (pc, d) s.retirement
  | _ -> true

(* Transactions are emitted in acceptance order, once complete and, if pinned to an instance, once it
   retired: a load retires after its data. *)
let rec release ~source ~region s out =
  match IM.min_binding_opt s.outbox with
  | Some (k, p) when ready s p ->
      let t = event ~source ~region s p in
      release ~source ~region
        { s with outbox = IM.remove k s.outbox; totals = account ~cycles:0 s.totals t }
        (Event.Transaction t :: out)
  | _ -> (s, out)

let step ~source ~region s cycle (sample, origins, queues, commits) =
  let s = retire s commits in
  let s = ops_step s cycle queues in
  let axi, evs = Axi4.step s.axi cycle sample in
  let s, out, accepted, completed =
    List.fold_left
      (fun (s, out, a, d) -> function
        | Axi4.Accepted (txn, x) ->
            let p = { txn; x; pin = origin_of txn origins s cycle; complete = false } in
            ({ s with outbox = IM.add x.serial p s.outbox }, out, a + 1, d)
        | Done (txn, x) ->
            let outbox =
              IM.update x.serial (Option.map (fun p -> { p with txn; complete = true })) s.outbox
            in
            ({ s with outbox }, out, a, d + 1)
        | Unmatched { cycle; write; id; what } ->
            ( { s with totals = { s.totals with t_unmatched = s.totals.t_unmatched + 1 } },
              Event.Unmatched { cycle; write; id; what } :: out,
              a,
              d )
        | Open_at_end _ -> (s, out, a, d))
      ({ s with axi }, [], 0, 0)
      evs
  in
  (* A request lasts while valid with the same address, direction and PC, until it is ready. *)
  let began =
    List.fold_left
      (fun began (id, (_, valid, ready, req)) ->
        match IM.find_opt id began with
        | _ when (not valid) || ready -> IM.remove id began
        | Some (r, _) when r = req -> began
        | _ -> IM.add id (req, cycle) began)
      s.began origins
  in
  let count = s.live + accepted and seen = s.seen || accepted > 0 in
  let add k n h =
    if n = 0 then h else IM.update k (fun c -> Some (n + Option.value c ~default:0)) h
  in
  let occupancy, zeros =
    if not seen then (s.occupancy, 0)
    else if count = 0 then (s.occupancy, s.zeros + 1)
    else (add count 1 (add 0 s.zeros s.occupancy), 0)
  in
  let s =
    {
      s with
      began;
      live = s.live + accepted - completed;
      seen;
      occupancy;
      zeros;
      last_cycle = cycle;
    }
  in
  let s, out = release ~source ~region s out in
  (s, List.rev out)

(* The end of the trace: unmatched write data, then what was not emitted, with the data that came. *)
let flush ~source ~region s =
  let evs = Axi4.finish s.axi in
  let outbox =
    List.fold_left
      (fun ob -> function
        | Axi4.Open_at_end (txn, x) -> IM.update x.serial (Option.map (fun p -> { p with txn })) ob
        | _ -> ob)
      s.outbox evs
  in
  List.filter_map
    (function
      | Axi4.Unmatched { cycle; write; id; what } ->
          Some (Event.Unmatched { cycle; write; id; what })
      | _ -> None)
    evs
  @ List.map (fun (_, p) -> Event.Transaction (event ~source ~region s p)) (IM.bindings outbox)

let zero =
  {
    t_reads = 0;
    t_read_bytes = 0;
    t_writes = 0;
    t_write_bytes = 0;
    t_unmatched = 0;
    t_rlat = Reduce.Stats.empty;
    t_wlat = Reduce.Stats.empty;
    t_incomplete = 0;
    t_first = max_int;
    t_last = 0;
    t_sources = SM.empty;
    t_pcs = IM.empty;
  }

let init =
  {
    axi = Axi4.init;
    waiting = IM.empty;
    recent = IM.empty;
    resyncs = 0;
    began = IM.empty;
    retirement = PM.empty;
    words = IM.empty;
    outbox = IM.empty;
    live = 0;
    occupancy = IM.empty;
    zeros = 0;
    seen = false;
    last_cycle = -1;
    totals = zero;
  }

let build (cfg : Config.t) (c : _ Core.t) =
  let a = Core.block c "axi_master" c.platform.blocks.axi_master in
  let sc = Core.scope c a.axi_scope in
  let wire n = a.axi_prefix ^ n in
  let r = Axi4.rdata sc (wire "read_data") in
  let w = Axi4.wdata sc (wire "write_data") ~data_bytes:a.data_bytes in
  let bch = Axi4.bresp sc (wire "write_resp") in
  (* Each originator's request as sampled. *)
  let origins =
    List.filter_map
      (fun (s : Platform.axi_source) ->
        Option.map
          (fun (o : Platform.origin) ->
            let os = Core.scope c o.o_scope in
            let opt n d =
              match n with
              | Some n -> Sig.map Option.some (Bind.signal os n d)
              | None -> Sig.const c.clk None
            in
            let open Sig in
            let+ valid = Bind.signal os o.o_valid Bind.bool
            and+ ready = Bind.signal os o.o_ready Bind.bool
            and+ addr = Bind.signal os o.o_addr Bind.uint
            and+ write = opt o.o_write Bind.bool
            and+ pc = opt o.o_pc Bind.uint in
            (s.source_id, (o.align, valid, ready, (addr, write, pc))))
          s.origin)
      a.sources
    |> Sig.all
  in
  let commits, commits_summary = Commits.events c in
  (* Each originator's operation queue: what enters it and what leaves it to make its requests. *)
  let lanes (p : Platform.port) =
    let ps = Core.scope c p.port_scope in
    List.init p.port_lanes (fun i ->
        let n x = Platform.name_of x i in
        let open Sig in
        let+ valid = Bind.signal ps (n p.port_valid) Bind.bool
        and+ ready = Bind.signal ps (n p.port_ready) Bind.bool
        and+ pc = Bind.signal ps (n p.port_pc) Bind.uint in
        if valid && ready then Some pc else None)
    |> Core.present c
  in
  let queues =
    List.filter_map
      (fun (s : Platform.axi_source) ->
        Option.bind s.origin (fun (o : Platform.origin) ->
            Option.map
              (fun (q : Platform.ops) ->
                Sig.map2 (fun e i -> (s.source_id, (e, i))) (lanes q.enqueue) (lanes q.issue))
              o.ops))
      a.sources
  in
  let queues = if queues = [] then Sig.const c.clk [] else Sig.all queues in
  let ar = Axi4.addr sc (wire "read_addr") in
  let aw = Axi4.addr sc (wire "write_addr") in
  let source id =
    List.find_opt (fun (s : Platform.axi_source) -> s.source_id = id) a.sources
    |> Option.map (fun (s : Platform.axi_source) -> s.source)
  in
  let region = cfg.region in
  let input =
    let open Sig in
    let+ sample = Axi4.sample { ar; aw; r; w; b = bch }
    and+ origins = origins
    and+ queues = queues
    and+ commits = Ev.current commits in
    (sample, origins, queues, commits)
  in
  let out, st =
    Machine.run
      {
        name;
        init;
        step = (fun ~tick s x -> step ~source ~region s tick.index x);
        finish = flush ~source ~region;
        every_tick = true;
      }
      input
  in
  let summary stats =
    let s = Sig.peek st in
    let cycles = s.last_cycle + 1 in
    let tot =
      List.fold_left
        (fun tot -> function
          | Event.Transaction t -> account ~cycles tot t
          | Unmatched _ -> { tot with t_unmatched = tot.t_unmatched + 1 })
        s.totals (flush ~source ~region s)
    in
    let words =
      List.fold_left (fun m (pc, w, _) -> IM.add pc w m) s.words (commits_summary stats).pending
    in
    let any = tot.t_reads + tot.t_writes > 0 in
    let occupancy =
      match IM.max_binding_opt s.occupancy with
      | None -> [ 0 ]
      | Some (top, _) ->
          List.init (top + 1) (fun k -> Option.value (IM.find_opt k s.occupancy) ~default:0)
    in
    let { Axi4.max_reads; max_writes } = Axi4.counts s.axi in
    {
      Summary.cycles;
      reads = tot.t_reads;
      read_bytes = tot.t_read_bytes;
      writes = tot.t_writes;
      write_bytes = tot.t_write_bytes;
      unmatched = tot.t_unmatched;
      read_latency = tot.t_rlat;
      write_latency = tot.t_wlat;
      incomplete = tot.t_incomplete;
      first = (if any then Some tot.t_first else None);
      last = (if any then Some tot.t_last else None);
      occupancy;
      max_reads;
      max_writes;
      sources =
        List.map
          (fun ((id, source), (transactions, bytes, pinned, instances, disagreeing)) ->
            { Summary.id; source; transactions; bytes; pinned; instances; disagreeing })
          (SM.bindings tot.t_sources);
      resyncs = s.resyncs;
      words =
        List.filter_map
          (fun (pc, ()) -> Option.map (fun w -> (pc, w)) (IM.find_opt pc words))
          (IM.bindings tot.t_pcs);
    }
  in
  (out, summary)

let text (ctx : Text.ctx) events (s : Summary.t) =
  let words = IM.of_seq (List.to_seq s.words) in
  let instruction pc =
    match IM.find_opt pc words with Some w -> ctx.disasm w | None -> "(not dispatched)"
  in
  let origin (t : Event.transaction) =
    match t.origin with
    | None -> "unpinned"
    | Some o ->
        let at =
          match o.instance with
          | Some i ->
              let at = function Some c -> string_of_int c | None -> "-" in
              Printf.sprintf "pc %08x %s (dispatched %s, op %s, retired %s)" i.pc (instruction i.pc)
                (at i.dispatched) (at i.issued) (at i.retired)
          | None -> Printf.sprintf "request %08x" o.request
        in
        if o.agrees then at
        else
          Printf.sprintf "%s; DISAGREES: request %s %08x" at
            (match o.write with Some true -> "W" | Some false -> "R" | None -> "?")
            o.request
  in
  let transactions =
    List.filter_map (function Event.Transaction t -> Some t | Unmatched _ -> None) events
  in
  let shown = ref 0 in
  Printf.printf "%8s %8s %8s %-3s %3s %-6s %-20s %5s %5s %7s %3s  %s\n" "start" "accept" "done"
    "dir" "id" "source" "addr" "bytes" "beats" "B/cycle" "out" "origin";
  List.iter
    (fun (t : Event.transaction) ->
      let pc = Option.value (Event.pc (Transaction t)) ~default:(-1) in
      if Text.selected ctx.window ~cycle:t.txn.accepted ~pc && !shown < ctx.limit then begin
        incr shown;
        Printf.printf "%8d %8d %8s %-3s %3d %-6s %-20s %5d %2dx%-2d %7s %3d  %s%s\n" (start t)
          t.txn.accepted
          (match t.txn.completed with Some c -> string_of_int c | None -> "-")
          (if t.txn.write then "W" else "R")
          t.txn.id
          (Option.value t.source ~default:"?")
          (Printf.sprintf "%08x%s" t.txn.address (Region.suffix ctx.region t.txn.address))
          t.txn.bytes t.txn.beats t.beat_bytes
          (match throughput t with Some r -> Printf.sprintf "%.2f" r | None -> "-")
          t.txn.outstanding (origin t)
          (if t.txn.status = 0 then "" else " " ^ resp_name t.txn.status)
      end)
    transactions;
  List.iter
    (function
      | Event.Unmatched u ->
          Printf.printf "%8d unmatched %s id %d: %s\n" u.cycle
            (if u.write then "W" else "R")
            u.id u.what
      | Transaction _ -> ())
    events;
  Printf.printf "root %s: reads %d (%d bytes), writes %d (%d bytes) in %d cycles, unmatched %d\n"
    ctx.root s.reads s.read_bytes s.writes s.write_bytes s.cycles s.unmatched;
  (match (s.first, s.last) with
  | Some first, Some last ->
      Printf.printf
        "  latency, address accepted to done, min/mean/max: reads %s, writes %s cycles%s\n"
        (Text.stats s.read_latency) (Text.stats s.write_latency)
        (if s.incomplete = 0 then ""
         else Printf.sprintf "; %d not done when the trace ends" s.incomplete);
      let busy = List.fold_left ( + ) 0 s.occupancy - List.hd s.occupancy in
      let total = s.read_bytes + s.write_bytes in
      Printf.printf
        "  throughput %.3f bytes/cycle over cycles %d-%d, %.3f while a transaction is outstanding \
         (%d cycles)\n"
        (float_of_int total /. float_of_int (last - first + 1))
        first last
        (if busy = 0 then 0. else float_of_int total /. float_of_int busy)
        busy;
      Printf.printf "  outstanding at once: max %d (reads %d, writes %d); cycles by count:%s\n"
        (List.length s.occupancy - 1)
        s.max_reads s.max_writes
        (String.concat "" (List.mapi (Printf.sprintf " %d:%d") s.occupancy));
      List.iter
        (fun (x : Summary.source) ->
          Printf.printf
            "  source %s (id %d): transactions %d, bytes %d, pinned to a request %d, to an \
             instruction instance %d%s\n"
            x.source x.id x.transactions x.bytes x.pinned x.instances
            (if x.disagreeing = 0 then "" else Printf.sprintf ", DISAGREEING %d" x.disagreeing))
        s.sources;
      if s.resyncs > 0 then Printf.printf "  queued operations that never issued: %d\n" s.resyncs
  | _ -> ());
  if ctx.profile > 0 then begin
    Printf.printf "external traffic by instruction:\n%8s %6s %7s %7s  %s\n" "pc" "count" "bytes"
      "cycles" "instruction";
    Profile.by_pc
      ~pc:(fun t -> Event.pc (Transaction t))
      ~weight:(fun (t : Event.transaction) -> t.txn.bytes)
      ~total:(fun t -> Option.value (span t) ~default:0)
      (List.to_seq transactions)
    |> List.iteri (fun i (r : int Profile.row) ->
        if i < ctx.profile then
          Printf.printf "%08x %6d %7d %7d  %s\n" r.key r.count r.weight r.total (instruction r.key))
  end
