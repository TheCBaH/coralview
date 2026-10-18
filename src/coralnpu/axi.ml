[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type origin = {
  issued : int;
  pc : int option;
  dispatched : int option;
  started : int option;
  retired : int option;
  o_addr : int;
  o_write : bool option;
  agrees : bool;
}

type transaction = {
  write : bool;
  id : int;
  source : string option;
  origin : origin option;
  addr : int;
  beats : int;
  beat_bytes : int;
  burst : int;
  bytes : int;
  requested : int;
  accepted : int;
  first_data : int option;
  completed : int option;
  resp : int;
  outstanding : int;
}

type unmatched = { u_cycle : int; u_write : bool; u_id : int; what : string }

type summary = {
  cycles : int;
  transactions : transaction list;
  unmatched : unmatched list;
  occupancy : int array;
  max_reads : int;
  max_writes : int;
  instructions : (int, int) Hashtbl.t;
  resyncs : int;
}

let model = "axi"
let needs = "axi_master" :: Commits.needs
let latency t = Option.map (fun c -> c - t.accepted) t.completed
let start t = match t.origin with Some o -> min o.issued t.requested | None -> t.requested
let span t = Option.map (fun c -> c - start t + 1) t.completed
let throughput t = Option.map (fun s -> float_of_int t.bytes /. float_of_int s) (span t)

let resp_name = function
  | 0 -> "OKAY"
  | 1 -> "EXOKAY"
  | 2 -> "SLVERR"
  | 3 -> "DECERR"
  | r -> string_of_int r

type addr = {
  a_fire : bool;
  a_valid : bool;
  a_addr : int;
  a_id : int;
  a_len : int;
  a_size : int;
  a_burst : int;
}

type rdata = { r_fire : bool; r_id : int; r_resp : int; r_last : bool }
type wdata = { w_fire : bool; w_strb : int; w_last : bool }
type bresp = { b_fire : bool; b_id : int; b_resp : int }

(* A transaction while it is outstanding. *)
type st = { mutable t : transaction; mutable data_beats : int }

(* A write data burst, possibly ahead of its address. *)
type wburst = { mutable wb_first : int; mutable wb_bytes : int; mutable wb_beats : int }

let popcount n =
  let rec go n k = if n = 0 then k else go (n land (n - 1)) (k + 1) in
  go n 0

let occupancy transactions ~cycles =
  let events =
    List.concat_map
      (fun t ->
        let last = Option.value t.completed ~default:(cycles - 1) in
        [ (t.accepted, 1); (last + 1, -1) ])
      transactions
    |> List.sort compare
  in
  let counts = Hashtbl.create 8 in
  let add k n =
    Hashtbl.replace counts k (n + Option.value (Hashtbl.find_opt counts k) ~default:0)
  in
  let rec walk level at = function
    | [] -> ()
    | (c, d) :: rest ->
        (match at with Some a when c > a -> add level (c - a) | _ -> ());
        walk (level + d) (Some c) rest
  in
  walk 0 None events;
  let top = Hashtbl.fold (fun k _ m -> max k m) counts 0 in
  Array.init (top + 1) (fun k -> Option.value (Hashtbl.find_opt counts k) ~default:0)

let graph (c : _ Core.t) f =
  let a = Core.block c "axi_master" c.platform.blocks.axi_master in
  let sc = Core.scope c a.axi_scope in
  let name n = a.axi_prefix ^ n in
  let b n = Bind.signal sc (name n) Bind.bool and u n = Bind.signal sc (name n) Bind.uint in
  let addr ch =
    let open Sig in
    let+ valid = b (ch ^ "_valid")
    and+ ready = b (ch ^ "_ready")
    and+ addr = u (ch ^ "_bits_addr")
    and+ id = u (ch ^ "_bits_id")
    and+ len = u (ch ^ "_bits_len")
    and+ size = u (ch ^ "_bits_size")
    and+ burst = u (ch ^ "_bits_burst") in
    {
      a_fire = valid && ready;
      a_valid = valid;
      a_addr = addr;
      a_id = id;
      a_len = len;
      a_size = size;
      a_burst = burst;
    }
  in
  let fire ch = Sig.map2 ( && ) (b (ch ^ "_valid")) (b (ch ^ "_ready")) in
  let rdata =
    let open Sig in
    let+ fire = fire "read_data"
    and+ id = u "read_data_bits_id"
    and+ resp = u "read_data_bits_resp"
    and+ last = b "read_data_bits_last" in
    { r_fire = fire; r_id = id; r_resp = resp; r_last = last }
  in
  let wdata =
    let open Sig in
    let+ fire = fire "write_data"
    and+ strb =
      Bind.signal sc (name "write_data_bits_strb") { Bind.uint with dwidth = Exact a.data_bytes }
    and+ last = b "write_data_bits_last" in
    { w_fire = fire; w_strb = strb; w_last = last }
  in
  let bresp =
    let open Sig in
    let+ fire = fire "write_resp"
    and+ id = u "write_resp_bits_id"
    and+ resp = u "write_resp_bits_resp" in
    { b_fire = fire; b_id = id; b_resp = resp }
  in
  (* Each originator's request as sampled, and the cycle the current one began. *)
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
  let began = Hashtbl.create 4 in
  let instructions = Hashtbl.create 256 in
  (* Each instruction instance's retirement, keyed by PC and dispatch cycle. *)
  let retirement = Hashtbl.create 1024 in
  let commits, commits_summary = Commits.events c in
  Ev.subscribe commits
    (List.iter (fun (k : Commits.commit) ->
         Option.iter (fun w -> Hashtbl.replace instructions k.pc w) k.word;
         Option.iter (fun d -> Hashtbl.replace retirement (k.pc, d) k.retired) k.dispatched));
  (* Each originator's operation queue: dispatched PCs waiting, in order, and the operations issued
     lately, newest first. *)
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
                (s.source_id, Sig.map2 (fun e i -> (e, i)) (lanes q.enqueue) (lanes q.issue)))
              o.ops))
      a.sources
  in
  let waiting = Hashtbl.create 2 and issued_ops = Hashtbl.create 2 and resyncs = ref 0 in
  List.iter
    (fun (id, _) ->
      Hashtbl.add waiting id (Queue.create ());
      Hashtbl.add issued_ops id [])
    queues;
  let queues = Sig.all (List.map (fun (id, s) -> Sig.map (fun x -> (id, x)) s) queues) in
  (* Issue first: an operation cannot leave the queue in the cycle it enters. A PC at the head that
     does not issue never will (a flush, or an operation with no requests): skip it. *)
  let ops_step cycle =
    List.iter (fun (id, (enq, iss)) ->
        let q = Hashtbl.find waiting id in
        List.iter
          (fun pc ->
            let rec take () =
              match Queue.take_opt q with
              | Some (p, d) when p = pc -> Some d
              | Some _ ->
                  incr resyncs;
                  take ()
              | None -> None
            in
            let d = take () in
            let recent = Hashtbl.find issued_ops id in
            Hashtbl.replace issued_ops id ((pc, d, cycle) :: List.filteri (fun i _ -> i < 15) recent))
          iss;
        List.iter (fun pc -> Queue.add (pc, cycle) q) enq)
  in
  let source id =
    List.find_opt (fun (s : Platform.axi_source) -> s.source_id = id) a.sources
    |> Option.map (fun (s : Platform.axi_source) -> s.source)
  in
  let reads = Hashtbl.create 4 and writes = Hashtbl.create 4 in
  let queue tbl id =
    match Hashtbl.find_opt tbl id with
    | Some q -> q
    | None ->
        let q = Queue.create () in
        Hashtbl.add tbl id q;
        q
  in
  let need_data = Queue.create () and early = Queue.create () in
  let burst = ref None in
  let accepted = ref [] and unmatched = ref [] in
  let reads_out = ref 0 and writes_out = ref 0 and max_reads = ref 0 and max_writes = ref 0 in
  let ar_since = ref None and aw_since = ref None and last_cycle = ref (-1) in
  let complete st cycle =
    st.t <- { st.t with completed = Some cycle };
    f st.t
  in
  let attach st wb =
    st.t <- { st.t with bytes = wb.wb_bytes; first_data = Some wb.wb_first };
    st.data_beats <- wb.wb_beats
  in
  let origin_of (ch : addr) ~write origins cycle =
    match List.assoc_opt ch.a_id origins with
    | Some (align, true, _, ((addr, w, pc) as req)) ->
        let issued =
          match Hashtbl.find_opt began ch.a_id with Some (r, at) when r = req -> at | _ -> cycle
        in
        let agrees =
          addr land lnot (align - 1) = ch.a_addr && Option.fold ~none:true ~some:(( = ) write) w
        in
        let dispatched, started =
          match (pc, Hashtbl.find_opt issued_ops ch.a_id) with
          | Some pc, Some recent -> (
              match List.find_opt (fun (p, _, at) -> p = pc && at <= issued) recent with
              | Some (_, d, at) -> (d, Some at)
              | None -> (None, None))
          | _ -> (None, None)
        in
        Some { issued; pc; dispatched; started; retired = None; o_addr = addr; o_write = w; agrees }
    | _ -> None
  in
  let accept (ch : addr) ~write ~since ~origins cycle =
    if write then incr writes_out else incr reads_out;
    max_reads := max !max_reads !reads_out;
    max_writes := max !max_writes !writes_out;
    let beats = ch.a_len + 1 and beat_bytes = 1 lsl ch.a_size in
    let st =
      {
        t =
          {
            write;
            id = ch.a_id;
            source = source ch.a_id;
            origin = origin_of ch ~write origins cycle;
            addr = ch.a_addr;
            beats;
            beat_bytes;
            burst = ch.a_burst;
            bytes = 0;
            requested = Option.value since ~default:cycle;
            accepted = cycle;
            first_data = None;
            completed = None;
            resp = 0;
            outstanding = !reads_out + !writes_out;
          };
        data_beats = 0;
      }
    in
    accepted := st :: !accepted;
    st
  in
  let since r (ch : addr) cycle =
    r := if ch.a_valid && not ch.a_fire then Some (Option.value !r ~default:cycle) else None
  in
  let step (cycle, ((ar, aw), (r, w), bch, origins, queues)) =
    last_cycle := cycle;
    ops_step cycle queues;
    let miss write id what =
      unmatched := { u_cycle = cycle; u_write = write; u_id = id; what } :: !unmatched
    in
    (* Responses first: none can belong to an address accepted in the same cycle. *)
    if r.r_fire then begin
      let q = queue reads r.r_id in
      match Queue.peek_opt q with
      | None -> miss false r.r_id "read data with no outstanding read"
      | Some st ->
          if st.t.first_data = None then st.t <- { st.t with first_data = Some cycle };
          st.data_beats <- st.data_beats + 1;
          st.t <- { st.t with bytes = st.t.bytes + st.t.beat_bytes; resp = max st.t.resp r.r_resp };
          if r.r_last then begin
            ignore (Queue.pop q);
            decr reads_out;
            complete st cycle
          end
    end;
    if bch.b_fire then begin
      let q = queue writes bch.b_id in
      match Queue.peek_opt q with
      | None -> miss true bch.b_id "write response with no outstanding write"
      | Some st ->
          ignore (Queue.pop q);
          decr writes_out;
          st.t <- { st.t with resp = max st.t.resp bch.b_resp };
          complete st cycle
    end;
    if w.w_fire then begin
      let wb =
        match !burst with
        | Some wb -> wb
        | None ->
            let wb = { wb_first = cycle; wb_bytes = 0; wb_beats = 0 } in
            burst := Some wb;
            wb
      in
      wb.wb_bytes <- wb.wb_bytes + popcount w.w_strb;
      wb.wb_beats <- wb.wb_beats + 1;
      if w.w_last then begin
        burst := None;
        match Queue.take_opt need_data with Some st -> attach st wb | None -> Queue.add wb early
      end
    end;
    if ar.a_fire then
      Queue.add (accept ar ~write:false ~since:!ar_since ~origins cycle) (queue reads ar.a_id);
    if aw.a_fire then begin
      let st = accept aw ~write:true ~since:!aw_since ~origins cycle in
      Queue.add st (queue writes aw.a_id);
      match Queue.take_opt early with Some wb -> attach st wb | None -> Queue.add st need_data
    end;
    since ar_since ar cycle;
    since aw_since aw cycle;
    (* A request lasts while valid with the same address, direction and PC, until it is ready. *)
    List.iter
      (fun (id, (_, valid, ready, req)) ->
        match Hashtbl.find_opt began id with
        | _ when (not valid) || ready -> Hashtbl.remove began id
        | Some (r, _) when r = req -> ()
        | _ -> Hashtbl.replace began id (req, cycle))
      origins
  in
  let sampled =
    let open Sig in
    let+ cycle = cycle c.clk
    and+ ar = addr "read_addr"
    and+ aw = addr "write_addr"
    and+ r = rdata
    and+ w = wdata
    and+ bch = bresp
    and+ origins = origins
    and+ queues = queues in
    (cycle, ((ar, aw), (r, w), bch, origins, queues))
  in
  Ev.subscribe (Ev.when_ (Sig.const c.clk true) sampled) step;
  fun stats ->
    let cycles = !last_cycle + 1 in
    Queue.iter
      (fun wb ->
        unmatched :=
          {
            u_cycle = wb.wb_first;
            u_write = true;
            u_id = -1;
            what = "write data with no write address";
          }
          :: !unmatched)
      early;
    List.iter
      (fun (pc, word, _) -> Hashtbl.replace instructions pc word)
      (commits_summary stats).pending;
    let instance (o : origin) =
      match (o.pc, o.dispatched) with
      | Some pc, Some d -> { o with retired = Hashtbl.find_opt retirement (pc, d) }
      | _ -> o
    in
    let transactions =
      List.rev_map (fun st -> { st.t with origin = Option.map instance st.t.origin }) !accepted
    in
    {
      cycles;
      transactions;
      unmatched = List.rev !unmatched;
      occupancy = occupancy transactions ~cycles;
      max_reads = !max_reads;
      max_writes = !max_writes;
      instructions;
      resyncs = !resyncs;
    }

let run p tr f =
  let (Core.Any c) = Core.bind p tr ~model in
  let finish = graph c f in
  finish (Core.run c)
