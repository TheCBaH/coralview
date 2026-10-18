[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

let name = "dma"

let doc =
  "DMA engine jobs: who started each, its descriptors, source, destination and size, every beat's \
   latency, completion and throughput, and when software saw it done."

let needs = [ "dma" ]

module IM = Map.Make (Int)

module Config = struct
  type t = { region : Region.t }

  let default = { region = Region.none }
end

module Descriptor = struct
  type t = {
    at : int;
    src : Access.t;
    dst : Access.t;
    len : int;
    beat : int;
    src_fixed : bool;
    dst_fixed : bool;
    poll : (int * int * int) option;
    next : int;
    fetch : Span.t;
  }

  let poll =
    Jsont.Object.map ~kind:"poll" (fun address mask value -> (address, mask, value))
    |> Jsont.Object.mem "address" Jsont.int ~enc:(fun (a, _, _) -> a)
    |> Jsont.Object.mem "mask" Jsont.int ~enc:(fun (_, m, _) -> m)
    |> Jsont.Object.mem "value" Jsont.int ~enc:(fun (_, _, v) -> v)
    |> Jsont.Object.finish

  let jsont =
    Jsont.Object.map ~kind:"descriptor"
      (fun at src dst len beat src_fixed dst_fixed poll next fetch ->
        { at; src; dst; len; beat; src_fixed; dst_fixed; poll; next; fetch })
    |> Jsont.Object.mem "at" Jsont.int ~enc:(fun d -> d.at)
    |> Jsont.Object.mem "src" Access.jsont ~enc:(fun d -> d.src)
    |> Jsont.Object.mem "dst" Access.jsont ~enc:(fun d -> d.dst)
    |> Jsont.Object.mem "len" Jsont.int ~enc:(fun d -> d.len)
    |> Jsont.Object.mem "beat" Jsont.int ~enc:(fun d -> d.beat)
    |> Jsont.Object.mem "src_fixed" Jsont.bool ~enc:(fun d -> d.src_fixed)
    |> Jsont.Object.mem "dst_fixed" Jsont.bool ~enc:(fun d -> d.dst_fixed)
    |> Codec.opt (fun d -> d.poll) "poll" poll
    |> Jsont.Object.mem "next" Jsont.int ~enc:(fun d -> d.next)
    |> Jsont.Object.mem "fetch" Codec.span ~enc:(fun d -> d.fetch)
    |> Jsont.Object.finish
end

module Event = struct
  type beat = { read : Transaction.t; write : Transaction.t option }
  type observed = { cycle : int; pc : int option }

  type job = {
    span : Span.t;
    pc : int option;
    first : int;
    descriptors : Descriptor.t list;
    beats : beat list;
    polls : int;
    error : bool;
    aborted : bool;
    status_reads : int;
    observed : observed option;
  }

  type stray = { cycle : int; what : string }
  type t = Job of job | Stray of stray

  let beat =
    Jsont.Object.map ~kind:"beat" (fun read write -> { read; write })
    |> Jsont.Object.mem "read" Codec.transaction ~enc:(fun b -> b.read)
    |> Codec.opt (fun b -> b.write) "write" Codec.transaction
    |> Jsont.Object.finish

  let observed =
    Jsont.Object.map ~kind:"observed" (fun cycle pc -> { cycle; pc })
    |> Jsont.Object.mem "cycle" Jsont.int ~enc:(fun (o : observed) -> o.cycle)
    |> Codec.opt (fun (o : observed) -> o.pc) "pc" Jsont.int
    |> Jsont.Object.finish

  let job =
    Codec.case "dma.job"
      (fun j -> Job j)
      (Jsont.Object.map
         (fun span pc first descriptors beats polls error aborted status_reads observed ->
           { span; pc; first; descriptors; beats; polls; error; aborted; status_reads; observed })
      |> Jsont.Object.mem "span" Codec.span ~enc:(fun j -> j.span)
      |> Codec.opt (fun j -> j.pc) "pc" Jsont.int
      |> Jsont.Object.mem "first" Jsont.int ~enc:(fun j -> j.first)
      |> Jsont.Object.mem "descriptors" (Jsont.list Descriptor.jsont) ~enc:(fun j -> j.descriptors)
      |> Jsont.Object.mem "beats" (Jsont.list beat) ~enc:(fun j -> j.beats)
      |> Jsont.Object.mem "polls" Jsont.int ~enc:(fun j -> j.polls)
      |> Jsont.Object.mem "error" Jsont.bool ~enc:(fun j -> j.error)
      |> Jsont.Object.mem "aborted" Jsont.bool ~enc:(fun j -> j.aborted)
      |> Jsont.Object.mem "status_reads" Jsont.int ~enc:(fun j -> j.status_reads)
      |> Codec.opt (fun j -> j.observed) "observed" observed
      |> Jsont.Object.finish)

  let stray =
    Codec.case "dma.stray"
      (fun s -> Stray s)
      (Jsont.Object.map (fun cycle what -> { cycle; what })
      |> Jsont.Object.mem "cycle" Jsont.int ~enc:(fun (s : stray) -> s.cycle)
      |> Jsont.Object.mem "what" Jsont.string ~enc:(fun (s : stray) -> s.what)
      |> Jsont.Object.finish)

  let jsont =
    Codec.cases "dma.event"
      (function
        | Job j -> Jsont.Object.Case.value job j | Stray s -> Jsont.Object.Case.value stray s)
      Jsont.Object.Case.[ make job; make stray ]

  let cycle = function Job j -> j.span.start | Stray s -> s.cycle
  let pc = function Job j -> j.pc | Stray _ -> None
end

let bytes (j : Event.job) =
  List.fold_left
    (fun n (b : Event.beat) -> match b.write with Some w -> n + w.bytes | None -> n)
    0 j.beats

module Summary = struct
  type t = { cycles : int; jobs : int; bytes : int; max_outstanding : int; stray : int }

  let jsont =
    Codec.record "dma.summary" (fun cycles jobs bytes max_outstanding stray ->
        { cycles; jobs; bytes; max_outstanding; stray })
    |> Jsont.Object.mem "cycles" Jsont.int ~enc:(fun s -> s.cycles)
    |> Jsont.Object.mem "jobs" Jsont.int ~enc:(fun s -> s.jobs)
    |> Jsont.Object.mem "bytes" Jsont.int ~enc:(fun s -> s.bytes)
    |> Jsont.Object.mem "max_outstanding" Jsont.int ~enc:(fun s -> s.max_outstanding)
    |> Jsont.Object.mem "stray" Jsont.int ~enc:(fun s -> s.stray)
    |> Jsont.Object.finish
end

(* CSR offsets and bits, from DmaEngine.scala. *)
let ctrl = 0x00
let status = 0x04
let desc_addr = 0x08
let half = 16

(* A job as it runs: [fetching] counts the descriptor halves still to come from [fetch_at]. *)
type running = {
  job : Event.job;
  fetching : int;
  fetch_at : int;
  fetch_start : int;
  half0 : Bits.t option;
  remaining : int;
  read : Tlul.transaction option;
  beats : (Tlul.transaction * Tlul.transaction option) list;  (** Newest first. *)
}

type state = {
  host : Tlul.state;
  device : Tlul.state;
  jobs : running IM.t;  (** Not emitted yet, by start order. *)
  serial : int;
  current : int option;  (** Running. *)
  latest : int option;  (** Started last: the one STATUS reads are about. *)
  desc : int;
  pcs : int option IM.t;  (** The instruction of each CSR request, by source. *)
  emitted : int;
  bytes : int;
  stray : int;
  last_cycle : int;
}

let field d lo width = Bits.field_int d ~lo ~width

let descriptor ~region ~at ~fetch d0 d1 =
  let poll_en = Bits.bit d0 93 in
  let len = field d0 64 24 in
  let access address write =
    { Access.address; bytes = len; write; region = Region.find region address }
  in
  {
    Descriptor.at;
    src = access (field d0 0 32) false;
    dst = access (field d0 32 32) true;
    len;
    beat = 1 lsl field d0 88 3;
    src_fixed = Bits.bit d0 91;
    dst_fixed = Bits.bit d0 92;
    poll = (if poll_en then Some (field d1 0 32, field d1 32 32, field d1 64 32) else None);
    next = field d0 96 32;
    fetch;
  }

let update s k f = { s with jobs = IM.update k (Option.map f) s.jobs }
let job_of s k = IM.find k s.jobs

let finish s k cycle ~error =
  let s =
    update s k (fun r ->
        {
          r with
          job =
            {
              r.job with
              span = { r.job.span with stop = Some cycle };
              error = r.job.error || error;
            };
        })
  in
  { s with current = None }

let on_device ~data_bytes ~stray cycle req s = function
  | Tlul.Accepted t ->
      let pc = match req with Some (addr, pc) when addr = t.request.address -> pc | _ -> None in
      { s with pcs = IM.add t.request.source pc s.pcs }
  | Tlul.Unmatched src ->
      stray (Printf.sprintf "CSR response for source %d" src);
      s
  | Tlul.Responded t ->
      let reg = t.request.address land 0xfff in
      let pc = Option.join (IM.find_opt t.request.source s.pcs) in
      if Tlul.is_get t.request then
        if reg <> status then s
        else
          match s.latest with
          | Some k when (job_of s k).job.observed = None ->
              let v = Tlul.value ~data_bytes t.request t.response in
              update s k (fun r ->
                  let j = { r.job with status_reads = r.job.status_reads + 1 } in
                  {
                    r with
                    job = (if v land 2 <> 0 then { j with observed = Some { cycle; pc } } else j);
                  })
          | _ -> s
      else
        let v = Tlul.value ~data_bytes t.request t.request.data in
        if reg = desc_addr then { s with desc = v }
        else if reg <> ctrl then s
        else
          let s =
            match s.current with
            | Some k when v land 4 <> 0 ->
                finish
                  (update s k (fun r -> { r with job = { r.job with aborted = true } }))
                  k cycle ~error:true
            | _ -> s
          in
          if v land 3 <> 3 then s
          else begin
            if s.current <> None then stray "start while a job runs";
            let r =
              {
                job =
                  {
                    span = { start = t.accepted; stop = None };
                    pc;
                    first = s.desc;
                    descriptors = [];
                    beats = [];
                    polls = 0;
                    error = false;
                    aborted = false;
                    status_reads = 0;
                    observed = None;
                  };
                fetching = 2;
                fetch_at = s.desc;
                fetch_start = t.accepted;
                half0 = None;
                remaining = 0;
                read = None;
                beats = [];
              }
            in
            let k = s.serial in
            { s with jobs = IM.add k r s.jobs; serial = k + 1; current = Some k; latest = Some k }
          end

let on_host ~region ~stray cycle s = function
  | Tlul.Accepted t -> (
      match s.current with
      | Some k ->
          let r = job_of s k in
          if r.fetching = 2 && r.half0 = None && t.request.address = r.fetch_at then
            update s k (fun r -> { r with fetch_start = t.requested })
          else s
      | None -> s)
  | Tlul.Unmatched src ->
      stray (Printf.sprintf "host response for source %d" src);
      s
  | Tlul.Responded t -> (
      let q = t.request in
      match s.current with
      | None ->
          stray
            (Printf.sprintf "host %s %08x with no job"
               (if Tlul.is_get q then "read" else "write")
               q.address);
          s
      | Some k -> (
          let r = job_of s k in
          if t.error then finish s k cycle ~error:true
          else if r.fetching > 0 then begin
            let expected = r.fetch_at + ((2 - r.fetching) * half) in
            if not (Tlul.is_get q && q.address = expected && q.size = half) then begin
              stray
                (Printf.sprintf "expected the descriptor read at %08x, got %08x" expected q.address);
              s
            end
            else
              match r.half0 with
              | None -> update s k (fun r -> { r with half0 = Some t.response; fetching = 1 })
              | Some d0 ->
                  let x =
                    descriptor ~region ~at:r.fetch_at
                      ~fetch:{ start = r.fetch_start; stop = Some cycle }
                      d0 t.response
                  in
                  update s k (fun r ->
                      {
                        r with
                        job = { r.job with descriptors = r.job.descriptors @ [ x ] };
                        half0 = None;
                        fetching = 0;
                        remaining = x.len;
                      })
          end
          else
            let x = List.nth r.job.descriptors (List.length r.job.descriptors - 1) in
            match (Tlul.is_get q, x.poll) with
            | true, Some (a, _, _) when q.address = a && r.read = None && q.size = 4 ->
                update s k (fun r -> { r with job = { r.job with polls = r.job.polls + 1 } })
            | true, _ ->
                if r.read <> None then stray "a second read before the write";
                update s k (fun r -> { r with read = Some t })
            | false, _ -> (
                match r.read with
                | None ->
                    stray (Printf.sprintf "write %08x with no read" q.address);
                    s
                | Some read ->
                    let remaining = r.remaining - q.size in
                    let s =
                      update s k (fun r ->
                          { r with read = None; beats = (read, Some t) :: r.beats; remaining })
                    in
                    if remaining > 0 then s
                    else if x.next <> 0 then
                      update s k (fun r ->
                          { r with fetching = 2; fetch_at = x.next; fetch_start = cycle })
                    else finish s k cycle ~error:false)))

let job (r : running) =
  let beats = match r.read with Some read -> (read, None) :: r.beats | None -> r.beats in
  {
    r.job with
    beats =
      List.rev_map
        (fun (read, write) ->
          { Event.read = Tlul.to_transaction read; write = Option.map Tlul.to_transaction write })
        beats;
  }

(* A job is complete once it no longer runs and software saw it done or started another: nothing
   changes it after that. Jobs complete in the order they started. *)
let rec release s out =
  match IM.min_binding_opt s.jobs with
  | Some (k, r) when s.current <> Some k && (r.job.observed <> None || s.latest <> Some k) ->
      let j = job r in
      release
        { s with jobs = IM.remove k s.jobs; emitted = s.emitted + 1; bytes = s.bytes + bytes j }
        (Event.Job j :: out)
  | _ -> (s, out)

let step ~host ~device ~data_bytes ~region s cycle (h, dv, req) =
  let out = ref [] in
  let stray what = out := Event.Stray { cycle; what } :: !out in
  let dst, devs = Tlul.step device s.device cycle dv in
  let s = List.fold_left (on_device ~data_bytes ~stray cycle req) { s with device = dst } devs in
  let hst, hevs = Tlul.step host s.host cycle h in
  let s = List.fold_left (on_host ~region ~stray cycle) { s with host = hst } hevs in
  let s = { s with stray = s.stray + List.length !out; last_cycle = cycle } in
  let s, out = release s !out in
  (s, List.rev out)

let flush s = List.map (fun (_, r) -> Event.Job (job r)) (IM.bindings s.jobs)

let build (cfg : Config.t) (c : _ Core.t) =
  let d = Core.block c "dma" c.platform.blocks.dma in
  let port (p : Platform.tlul) =
    Tlul.bind (Core.scope c d.dma_scope)
      { prefix = p.tl_prefix; d_ready = p.d_ready }
      ~data_bytes:p.tl_data_bytes
  in
  let host = port d.host and device = port d.device in
  let requester =
    match d.requester with
    | None -> Sig.const c.clk None
    | Some o ->
        let os = Core.scope c o.o_scope in
        let pc =
          match o.o_pc with
          | Some n -> Sig.map Option.some (Bind.signal os n Bind.uint)
          | None -> Sig.const c.clk None
        in
        let open Sig in
        let+ valid = Bind.signal os o.o_valid Bind.bool
        and+ addr = Bind.signal os o.o_addr Bind.uint
        and+ pc = pc in
        if valid && addr land lnot 0xfff = d.csr_base then Some (addr, pc) else None
  in
  let input =
    let open Sig in
    let+ h = Tlul.sample host and+ dv = Tlul.sample device and+ req = requester in
    (h, dv, req)
  in
  let init =
    {
      host = Tlul.init;
      device = Tlul.init;
      jobs = IM.empty;
      serial = 0;
      current = None;
      latest = None;
      desc = 0;
      pcs = IM.empty;
      emitted = 0;
      bytes = 0;
      stray = 0;
      last_cycle = -1;
    }
  in
  let step = step ~host ~device ~data_bytes:d.device.tl_data_bytes ~region:cfg.region in
  let out, st =
    Machine.run
      {
        name;
        init;
        step = (fun ~tick s x -> step s tick.index x);
        finish = flush;
        every_tick = true;
      }
      input
  in
  let summary _ =
    let s = Sig.peek st in
    let rest = List.map (fun (_, r) -> job r) (IM.bindings s.jobs) in
    {
      Summary.cycles = s.last_cycle + 1;
      jobs = s.emitted + List.length rest;
      bytes = List.fold_left (fun n j -> n + bytes j) s.bytes rest;
      max_outstanding = Tlul.max_outstanding s.host;
      stray = s.stray;
    }
  in
  (out, summary)

let text (ctx : Text.ctx) ~beats events (s : Summary.t) =
  let region = Region.suffix ctx.region in
  let at = function Some c -> string_of_int c | None -> "-" in
  let pc = function Some pc -> Printf.sprintf " by pc %08x" pc | None -> "" in
  let stats l =
    match l with
    | [] -> "-"
    | l ->
        Printf.sprintf "%d/%.1f/%d" (List.fold_left min max_int l)
          (float_of_int (List.fold_left ( + ) 0 l) /. float_of_int (List.length l))
          (List.fold_left max 0 l)
  in
  let lat (t : Transaction.t) = Transaction.latency t in
  let rate b c = if c <= 0 then 0. else float_of_int b /. float_of_int c in
  let jobs = List.filter_map (function Event.Job j -> Some j | Stray _ -> None) events in
  List.iteri
    (fun i (j : Event.job) ->
      Printf.printf "job %d: started %d%s, descriptor %08x%s\n" (i + 1) j.span.start (pc j.pc)
        j.first
        (if j.aborted then ", ABORTED" else if j.error then ", ERROR" else "");
      List.iter
        (fun (x : Descriptor.t) ->
          Printf.printf
            "  descriptor %08x fetched %d-%d: %08x%s%s -> %08x%s%s, %d bytes in %d-byte beats%s%s\n"
            x.at x.fetch.start
            (Option.value x.fetch.stop ~default:x.fetch.start)
            x.src.address (region x.src.address)
            (if x.src_fixed then " fixed" else "")
            x.dst.address (region x.dst.address)
            (if x.dst_fixed then " fixed" else "")
            x.len x.beat
            (match x.poll with
            | Some (a, m, v) -> Printf.sprintf ", polls %08x & %08x = %08x" a m v
            | None -> "")
            (if x.next <> 0 then Printf.sprintf ", next %08x" x.next else ""))
        j.descriptors;
      let reads = List.filter_map (fun (b : Event.beat) -> lat b.read) j.beats
      and writes = List.filter_map (fun (b : Event.beat) -> Option.bind b.write lat) j.beats in
      (match j.beats with
      | [] -> Printf.printf "  no data beats\n"
      | first :: _ ->
          let last = List.nth j.beats (List.length j.beats - 1) in
          let ends = match last.write with Some w -> w.completed | None -> last.read.completed in
          let data_cycles = Option.map (fun e -> e - first.read.requested + 1) ends in
          let n = List.length j.beats in
          Printf.printf
            "  beats %d, cycles %d-%s%s: latency, request accepted to response, min/mean/max reads \
             %s, writes %s; %.3f bytes/cycle%s\n"
            n first.read.requested (at ends)
            (if n > 1 then
               Printf.sprintf ", one every %.1f cycles"
                 (float_of_int (last.read.accepted - first.read.accepted) /. float_of_int (n - 1))
             else "")
            (stats reads) (stats writes)
            (rate (bytes j) (Option.value data_cycles ~default:0))
            (if j.polls > 0 then Printf.sprintf ", %d polls" j.polls else ""));
      List.iteri
        (fun k (b : Event.beat) ->
          if k < beats then
            Printf.printf "    %8d read %08x %d bytes, response %s%s\n" b.read.accepted
              b.read.address b.read.bytes (at b.read.completed)
              (match b.write with
              | Some w ->
                  Printf.sprintf "; write %08x accepted %d, response %s" w.address w.accepted
                    (at w.completed)
              | None -> "; no write"))
        j.beats;
      (match j.span.stop with
      | Some f ->
          Printf.printf "  finished %d: %d bytes, %d cycles from start, %.3f bytes/cycle\n" f
            (bytes j)
            (f - j.span.start + 1)
            (rate (bytes j) (f - j.span.start + 1))
      | None -> Printf.printf "  not finished when the trace ends: %d bytes moved\n" (bytes j));
      match j.observed with
      | Some o ->
          Printf.printf "  software saw done at %d%s, %d cycles after the start, %d STATUS reads\n"
            o.cycle (pc o.pc) (o.cycle - j.span.start) j.status_reads
      | None -> Printf.printf "  software never saw done; %d STATUS reads\n" j.status_reads)
    jobs;
  List.iter
    (function Event.Stray x -> Printf.printf "%8d stray: %s\n" x.cycle x.what | Job _ -> ())
    events;
  Printf.printf
    "root %s: jobs %d, %d bytes in %d cycles, host port at most %d outstanding, %d stray\n" ctx.root
    s.jobs s.bytes s.cycles s.max_outstanding s.stray
