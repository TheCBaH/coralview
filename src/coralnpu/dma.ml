[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type descriptor = {
  at : int;
  src : int;
  dst : int;
  len : int;
  beat : int;
  src_fixed : bool;
  dst_fixed : bool;
  poll : (int * int * int) option;
  next : int;
  fetch : int * int;
}

type beat = { read : Tlul.transaction; write : Tlul.transaction option }

type job = {
  started : int;
  pc : int option;
  first : int;
  descriptors : descriptor list;
  beats : beat list;
  polls : int;
  finished : int option;
  error : bool;
  aborted : bool;
  status_reads : int;
  observed : (int * int option) option;
}

type summary = { cycles : int; jobs : job list; stray : (int * string) list; max_outstanding : int }

let model = "dma"
let needs = [ "dma" ]

let bytes j =
  List.fold_left
    (fun n b -> match b.write with Some w -> n + w.request.size | None -> n)
    0 j.beats

let latency j = Option.map (fun f -> f - j.started) j.finished

(* CSR offsets and bits, from DmaEngine.scala. *)
let ctrl = 0x00
let status = 0x04
let desc_addr = 0x08
let half = 16

(* A job as it runs: [fetching] counts the descriptor halves still to come from [fetch_at]. *)
type running = {
  mutable job : job;
  mutable fetching : int;
  mutable fetch_at : int;
  mutable fetch_start : int;
  mutable half0 : Bits.t option;
  mutable remaining : int;
  mutable read : Tlul.transaction option;
}

let field d lo width = Bits.field_int d ~lo ~width

let descriptor ~at ~fetch d0 d1 =
  let poll_en = Bits.bit d0 93 in
  {
    at;
    src = field d0 0 32;
    dst = field d0 32 32;
    len = field d0 64 24;
    beat = 1 lsl field d0 88 3;
    src_fixed = Bits.bit d0 91;
    dst_fixed = Bits.bit d0 92;
    poll = (if poll_en then Some (field d1 0 32, field d1 32 32, field d1 64 32) else None);
    next = field d0 96 32;
    fetch;
  }

let graph (c : _ Core.t) =
  let d = Core.block c "dma" c.platform.blocks.dma in
  let host = Tlul.bind c d.dma_scope d.host and device = Tlul.bind c d.dma_scope d.device in
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
  let jobs = ref [] and current = ref None and stray = ref [] and last_cycle = ref (-1) in
  let desc = ref 0 and pcs = Hashtbl.create 4 in
  let latest = ref None in
  let finish r cycle ~error =
    r.job <- { r.job with finished = Some cycle; error = r.job.error || error };
    current := None
  in
  let value p (t : Tlul.transaction) data = Tlul.value ~data_bytes:p t.request data in
  let on_device cycle req = function
    | Tlul.Accepted t ->
        let pc = match req with Some (addr, pc) when addr = t.request.address -> pc | _ -> None in
        Hashtbl.replace pcs t.request.source pc
    | Tlul.Unmatched s -> stray := (cycle, Printf.sprintf "CSR response for source %d" s) :: !stray
    | Tlul.Responded t ->
        let reg = t.request.address land 0xfff in
        let pc = Option.join (Hashtbl.find_opt pcs t.request.source) in
        if Tlul.is_get t.request then begin
          if reg = status then
            match !latest with
            | Some r when r.job.observed = None ->
                let s = value d.device.tl_data_bytes t t.response in
                r.job <- { r.job with status_reads = r.job.status_reads + 1 };
                if s land 2 <> 0 then r.job <- { r.job with observed = Some (cycle, pc) }
            | _ -> ()
        end
        else
          let v = value d.device.tl_data_bytes t t.request.data in
          if reg = desc_addr then desc := v
          else if reg = ctrl then begin
            (match !current with
            | Some r when v land 4 <> 0 ->
                r.job <- { r.job with aborted = true };
                finish r cycle ~error:true
            | _ -> ());
            if v land 3 = 3 then begin
              if !current <> None then stray := (cycle, "start while a job runs") :: !stray;
              let r =
                {
                  job =
                    {
                      started = t.accepted;
                      pc;
                      first = !desc;
                      descriptors = [];
                      beats = [];
                      polls = 0;
                      finished = None;
                      error = false;
                      aborted = false;
                      status_reads = 0;
                      observed = None;
                    };
                  fetching = 2;
                  fetch_at = !desc;
                  fetch_start = t.accepted;
                  half0 = None;
                  remaining = 0;
                  read = None;
                }
              in
              current := Some r;
              latest := Some r;
              jobs := r :: !jobs
            end
          end
  in
  let on_host cycle = function
    | Tlul.Accepted t -> (
        match !current with
        | Some r when r.fetching = 2 && r.half0 = None && t.request.address = r.fetch_at ->
            r.fetch_start <- t.requested
        | _ -> ())
    | Tlul.Unmatched s -> stray := (cycle, Printf.sprintf "host response for source %d" s) :: !stray
    | Tlul.Responded t -> (
        let q = t.request in
        match !current with
        | None ->
            stray :=
              ( cycle,
                Printf.sprintf "host %s %08x with no job"
                  (if Tlul.is_get q then "read" else "write")
                  q.address )
              :: !stray
        | Some r -> (
            if t.error then finish r cycle ~error:true
            else if r.fetching > 0 then begin
              let expected = r.fetch_at + ((2 - r.fetching) * half) in
              if not (Tlul.is_get q && q.address = expected && q.size = half) then
                stray :=
                  ( cycle,
                    Printf.sprintf "expected the descriptor read at %08x, got %08x" expected
                      q.address )
                  :: !stray
              else
                match r.half0 with
                | None ->
                    r.half0 <- Some t.response;
                    r.fetching <- 1
                | Some d0 ->
                    let x = descriptor ~at:r.fetch_at ~fetch:(r.fetch_start, cycle) d0 t.response in
                    r.job <- { r.job with descriptors = r.job.descriptors @ [ x ] };
                    r.half0 <- None;
                    r.fetching <- 0;
                    r.remaining <- x.len
            end
            else
              let x = List.nth r.job.descriptors (List.length r.job.descriptors - 1) in
              match (Tlul.is_get q, x.poll) with
              | true, Some (a, _, _) when q.address = a && r.read = None && q.size = 4 ->
                  r.job <- { r.job with polls = r.job.polls + 1 }
              | true, _ ->
                  if r.read <> None then
                    stray := (cycle, "a second read before the write") :: !stray;
                  r.read <- Some t
              | false, _ -> (
                  match r.read with
                  | None ->
                      stray := (cycle, Printf.sprintf "write %08x with no read" q.address) :: !stray
                  | Some read ->
                      r.read <- None;
                      r.job <- { r.job with beats = r.job.beats @ [ { read; write = Some t } ] };
                      r.remaining <- r.remaining - q.size;
                      if r.remaining <= 0 then
                        if x.next <> 0 then begin
                          r.fetching <- 2;
                          r.fetch_at <- x.next;
                          r.fetch_start <- cycle
                        end
                        else finish r cycle ~error:false)))
  in
  let sampled =
    let open Sig in
    let+ cycle = cycle c.clk
    and+ h = Tlul.sample host
    and+ dv = Tlul.sample device
    and+ req = requester in
    (cycle, h, dv, req)
  in
  Ev.subscribe
    (Ev.when_ (Sig.const c.clk true) sampled)
    (fun (cycle, h, dv, req) ->
      last_cycle := cycle;
      List.iter (on_device cycle req) (Tlul.step device cycle dv);
      List.iter (on_host cycle) (Tlul.step host cycle h));
  fun _ ->
    let jobs =
      List.rev_map
        (fun r ->
          match r.read with
          | Some read -> { r.job with beats = r.job.beats @ [ { read; write = None } ] }
          | None -> r.job)
        !jobs
    in
    {
      cycles = !last_cycle + 1;
      jobs;
      stray = List.rev !stray;
      max_outstanding = Tlul.max_outstanding host;
    }

let run p tr =
  let (Core.Any c) = Core.bind p tr ~model in
  let finish = graph c in
  finish (Core.run c)
