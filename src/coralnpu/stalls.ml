[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type reason =
  | Dispatched
  | Empty
  | Behind
  | Halted
  | Interlock
  | Raw
  | Waw
  | Float_hazard
  | Lsu_queue
  | Rvv_queue
  | Rob_full
  | Trap_pending
  | Csr_serialize
  | Unit_busy
  | Other

let reason_name = function
  | Dispatched -> "dispatched"
  | Empty -> "empty"
  | Behind -> "behind"
  | Halted -> "halted"
  | Interlock -> "interlock"
  | Raw -> "raw"
  | Waw -> "waw"
  | Float_hazard -> "float-hazard"
  | Lsu_queue -> "lsu-queue"
  | Rvv_queue -> "rvv-queue"
  | Rob_full -> "rob-full"
  | Trap_pending -> "trap-pending"
  | Csr_serialize -> "csr-serialize"
  | Unit_busy -> "unit-busy"
  | Other -> "other"

let reasons =
  [
    Dispatched;
    Empty;
    Behind;
    Halted;
    Interlock;
    Raw;
    Waw;
    Float_hazard;
    Lsu_queue;
    Rvv_queue;
    Rob_full;
    Trap_pending;
    Csr_serialize;
    Unit_busy;
    Other;
  ]

type lane = { lane : int; pc : int; word : int; reason : reason }

let name = "stalls"
let doc = "Why each dispatch lane did not dispatch."
let needs = [ "dispatch" ]

module Config = struct
  type t = unit

  let default = ()
end

module Event = struct
  type stall_span = { lane : int; reason : reason; pc : int; word : int; span : Span.t }
  type t = Stall_span of stall_span

  let reason = Jsont.enum ~kind:"reason" (List.map (fun r -> (reason_name r, r)) reasons)

  let stall_span =
    Codec.case "stalls.span"
      (fun s -> Stall_span s)
      (Jsont.Object.map (fun lane reason pc word span -> { lane; reason; pc; word; span })
      |> Jsont.Object.mem "lane" Jsont.int ~enc:(fun s -> s.lane)
      |> Jsont.Object.mem "reason" reason ~enc:(fun s -> s.reason)
      |> Jsont.Object.mem "pc" Jsont.int ~enc:(fun s -> s.pc)
      |> Jsont.Object.mem "word" Jsont.int ~enc:(fun s -> s.word)
      |> Jsont.Object.mem "span" Codec.span ~enc:(fun s -> s.span)
      |> Jsont.Object.finish)

  let jsont =
    Codec.cases "stalls.event"
      (function Stall_span s -> Jsont.Object.Case.value stall_span s)
      Jsont.Object.Case.[ make stall_span ]

  let cycle (Stall_span s) = s.span.start
  let pc (Stall_span s) = Some s.pc
end

module Summary = struct
  type count = { lane : int; reason : reason; cycles : int }
  type t = { cycles : int; counts : count list  (** By lane, then reason. *) }

  let count =
    Jsont.Object.map ~kind:"count" (fun lane reason cycles -> { lane; reason; cycles })
    |> Jsont.Object.mem "lane" Jsont.int ~enc:(fun (c : count) -> c.lane)
    |> Jsont.Object.mem "reason" Event.reason ~enc:(fun (c : count) -> c.reason)
    |> Jsont.Object.mem "cycles" Jsont.int ~enc:(fun (c : count) -> c.cycles)
    |> Jsont.Object.finish

  let jsont =
    Codec.record "stalls.summary" (fun cycles counts -> { cycles; counts })
    |> Jsont.Object.mem "cycles" Jsont.int ~enc:(fun (s : t) -> s.cycles)
    |> Jsont.Object.mem "counts" (Jsont.list count) ~enc:(fun s -> s.counts)
    |> Jsont.Object.finish
end

(* Register use by major opcode, as Decode.scala's decodedInsts flags. *)
let opcode w = w land 0x7f
let f3 w = (w lsr 12) land 7
let rd w = (w lsr 7) land 31
let rs1 w = (w lsr 15) land 31
let rs2 w = (w lsr 20) land 31
let is_vector_mem w = (opcode w = 0x07 || opcode w = 0x27) && not (List.mem (f3 w) [ 1; 2; 3; 4 ])
let is_lsu w = List.mem (opcode w) [ 0x03; 0x23; 0x07; 0x27; 0x0f ] || opcode w = 0x2f
let is_rvv w = opcode w = 0x57 || opcode w = 0x77 || is_vector_mem w
let is_csr w = opcode w = 0x73 && f3 w <> 0

let is_float w =
  List.mem (opcode w) [ 0x07; 0x27; 0x43; 0x47; 0x4b; 0x4f; 0x53 ] && not (is_vector_mem w)

let reads_rs1 w =
  match opcode w with
  | 0x33 | 0x3b | 0x13 | 0x1b | 0x03 | 0x23 | 0x63 | 0x67 | 0x07 | 0x27 | 0x2f -> true
  | 0x73 -> List.mem (f3 w) [ 1; 2; 3 ]
  | _ -> false

let reads_rs2 w = List.mem (opcode w) [ 0x33; 0x3b; 0x23; 0x63; 0x2f ]
let reads_regd w = opcode w = 0x67 || is_lsu w

let writes_rd w =
  match opcode w with
  | 0x33 | 0x3b | 0x13 | 0x1b | 0x03 | 0x37 | 0x17 | 0x6f | 0x67 | 0x2f -> rd w <> 0
  | 0x73 -> f3 w <> 0 && rd w <> 0
  | _ -> false

let bit mask r = (mask lsr r) land 1 = 1

type port = {
  valid : bool;
  ready : bool;
  try_ : bool;
  pc : int;
  word : int;
  comb : int;
  fcomb : int;
}

type core = {
  halted : bool;
  interlock : bool;
  regd : int;
  n_space : int;
  rob_empty : bool;
  trap_pending : bool;
  lsu_cap : int;
  rvv_cap : int;
}

let classify core ports =
  let older = Array.of_list ports in
  List.mapi
    (fun i p ->
      let count f =
        Array.fold_left (fun n (q : port) -> if f q.word then n + 1 else n) 0 (Array.sub older 0 i)
      in
      let w = p.word in
      let reason =
        if not p.valid then Empty
        else if p.ready then Dispatched
        else if i > 0 && not older.(i - 1).ready then Behind
        else if p.try_ then Unit_busy
        else if core.halted then Halted
        else if core.interlock then Interlock
        else if
          (reads_rs1 w && bit (p.comb lor if reads_regd w then core.regd else 0) (rs1 w))
          || (reads_rs2 w && bit (p.comb lor if reads_regd w then core.regd else 0) (rs2 w))
        then Raw
        else if writes_rd w && bit p.comb (rd w) then Waw
        else if
          is_float w && p.fcomb <> 0
          && (bit p.fcomb (rs1 w) || bit p.fcomb (rs2 w) || bit p.fcomb (rd w))
        then Float_hazard
        else if count is_lsu >= core.lsu_cap then Lsu_queue
        else if count is_rvv >= core.rvv_cap then Rvv_queue
        else if i >= core.n_space then Rob_full
        else if core.trap_pending then Trap_pending
        else if is_csr w && not core.rob_empty then Csr_serialize
        else Other
      in
      { lane = i; pc = p.pc; word = w; reason })
    ports

module CM = Map.Make (struct
  type t = int * reason

  let compare = compare
end)

type state = {
  open_ : (lane * int) list;  (** Per lane, in lane order: the span running and its start. *)
  counts : int CM.t;
  ticks : int;
  last : int;
}

let span_of ((l : lane), start) stop =
  Event.Stall_span
    { lane = l.lane; reason = l.reason; pc = l.pc; word = l.word; span = { start; stop } }

let same (a : lane) (b : lane) = a.reason = b.reason && a.pc = b.pc && a.word = b.word

(* Runs of a lane with the same reason and instruction; one ends when the next sample differs. *)
let step s cycle lanes =
  let counts =
    List.fold_left
      (fun m (l : lane) ->
        CM.update (l.lane, l.reason) (fun n -> Some (1 + Option.value n ~default:0)) m)
      s.counts lanes
  in
  let rec go prev lanes acc out =
    match (prev, lanes) with
    | ((p, start) as run) :: prev, l :: lanes ->
        if same p l then go prev lanes (run :: acc) out
        else go prev lanes ((l, cycle) :: acc) (span_of run (Some (cycle - 1)) :: out)
    | [], l :: lanes -> go [] lanes ((l, cycle) :: acc) out
    | run :: prev, [] -> go prev [] acc (span_of run (Some (cycle - 1)) :: out)
    | [], [] -> (List.rev acc, List.rev out)
  in
  let open_, out = go s.open_ lanes [] [] in
  ({ open_; counts; ticks = s.ticks + 1; last = cycle }, out)

let make (c : _ Core.t) =
  let d = Core.block c "dispatch" c.platform.blocks.dispatch in
  let sc = Core.scope c d.d_scope in
  let b name = Bind.signal sc name Bind.bool in
  let u name = Bind.signal sc name Bind.uint in
  let lanes = List.init d.d_lanes Fun.id in
  let ports =
    List.map
      (fun i ->
        let open Sig in
        let p = Printf.sprintf "io_inst_%d_" i in
        let+ valid = b (p ^ "valid")
        and+ ready = b (p ^ "ready")
        and+ try_ = b (List.nth d.try_dispatch i)
        and+ pc = u (p ^ "bits_addr")
        and+ word = u (p ^ "bits_inst")
        and+ comb = u (List.nth d.comb i)
        and+ fcomb = match d.fcomb with Some l -> u (List.nth l i) | None -> Sig.const c.clk 0 in
        { valid; ready; try_; pc; word; comb; fcomb })
      lanes
  in
  let core =
    let open Sig in
    let+ halted = b "io_halted"
    and+ interlock = b "io_interlock"
    and+ regd = u "io_scoreboard_regd"
    and+ n_space = u "io_retirement_buffer_nSpace"
    and+ rob_empty = b "io_retirement_buffer_empty"
    and+ trap_pending = b "io_retirement_buffer_trap_pending"
    and+ lsu_cap = u "io_lsuQueueCapacity"
    and+ rvv_cap = match d.rvv_queue with Some w -> u w | None -> Sig.const c.clk max_int in
    { halted; interlock; regd; n_space; rob_empty; trap_pending; lsu_cap; rvv_cap }
  in
  let lanes =
    Sig.map2 classify core (match ports with [] -> Sig.const c.clk [] | p -> Sig.all p)
  in
  let out, st =
    Machine.run
      {
        name;
        init = { open_ = []; counts = CM.empty; ticks = 0; last = -1 };
        step = (fun ~tick s l -> step s tick.index l);
        finish = (fun s -> List.map (fun run -> span_of run None) s.open_);
        every_tick = true;
      }
      lanes
  in
  let summary (st' : Sched.run_stats) =
    let s = Sig.peek st in
    {
      Summary.cycles = st'.ticks.(0);
      counts =
        List.map
          (fun ((lane, reason), cycles) -> { Summary.lane; reason; cycles })
          (CM.bindings s.counts);
    }
  in
  (out, summary)

type 'c Core.dep += Shared of ((Event.t list, 'c) Ev.t * (Sched.run_stats -> Summary.t))

let build () c =
  Analysis.shared c name
    ~inj:(fun x -> Shared x)
    ~prj:(function Shared x -> Some x | _ -> None)
    (fun () -> make c)

let profile (ctx : Text.ctx) events (s : Summary.t) =
  let blocked =
    List.filter_map
      (fun (Event.Stall_span x) ->
        if x.lane = 0 && x.reason <> Dispatched && x.reason <> Empty then Some x else None)
      events
    |> List.stable_sort (fun (a : Event.stall_span) b -> Int.compare a.span.start b.span.start)
  in
  Printf.printf "lane 0 blocked, by instruction:\n%8s %6s %-14s %s\n" "pc" "cycles" "reason"
    "instruction";
  Profile.by
    ~key:(fun (x : Event.stall_span) -> Some (x.pc, x.word, x.reason))
    ~weight:(fun (x : Event.stall_span) ->
      Option.value x.span.stop ~default:(s.cycles - 1) - x.span.start + 1)
    (List.to_seq blocked)
  |> List.iteri (fun i (r : _ Profile.row) ->
      let pc, word, reason = r.key in
      if i < ctx.profile then
        Printf.printf "%08x %6d %-14s %s\n" pc r.weight (reason_name reason) (ctx.disasm word))

let text (ctx : Text.ctx) events (s : Summary.t) =
  let count lane r =
    List.find_map
      (fun (c : Summary.count) -> if c.lane = lane && c.reason = r then Some c.cycles else None)
      s.counts
  in
  let lanes = List.fold_left (fun n (c : Summary.count) -> max n (c.lane + 1)) 0 s.counts in
  Printf.printf "root %s: %d cycles\n%-14s" ctx.root s.cycles "reason";
  for l = 0 to lanes - 1 do
    Printf.printf " %7s" (Printf.sprintf "lane%d" l)
  done;
  print_newline ();
  List.iter
    (fun r ->
      if List.exists (fun l -> count l r <> None) (List.init lanes Fun.id) then begin
        Printf.printf "%-14s" (reason_name r);
        for l = 0 to lanes - 1 do
          Printf.printf " %7d" (Option.value (count l r) ~default:0)
        done;
        print_newline ()
      end)
    reasons;
  if ctx.profile > 0 then profile ctx events s

let perfetto (ctx : Text.ctx) events (s : Summary.t) =
  {
    Perfetto.process = "stalls " ^ ctx.root;
    slices =
      List.map
        (fun (Event.Stall_span x) ->
          {
            Perfetto.track = Printf.sprintf "lane %d" x.lane;
            name = reason_name x.reason;
            start = x.span.start;
            stop = Option.value x.span.stop ~default:(s.cycles - 1);
            args = [ ("pc", Printf.sprintf "%08x" x.pc); ("instruction", ctx.disasm x.word) ];
          })
        events;
    counters = [];
  }

module Accumulator = struct
  type event = Event.t
  type open_span = { lane : int; reason : reason; start : int }
  type snapshot = { spans : int; counts : Summary.count list; open_spans : open_span list }
  type t = { mutable spans : int; mutable counts : int CM.t; mutable open_ : open_span list }

  let create () = { spans = 0; counts = CM.empty; open_ = [] }

  let add t (Event.Stall_span s) =
    match s.span.stop with
    | Some stop ->
        t.spans <- t.spans + 1;
        t.counts <-
          CM.update (s.lane, s.reason)
            (fun n -> Some (stop - s.span.start + 1 + Option.value n ~default:0))
            t.counts
    | None -> t.open_ <- { lane = s.lane; reason = s.reason; start = s.span.start } :: t.open_

  let snapshot t =
    {
      spans = t.spans;
      counts =
        List.map
          (fun ((lane, reason), cycles) -> { Summary.lane; reason; cycles })
          (CM.bindings t.counts);
      open_spans = List.rev t.open_;
    }

  let open_span =
    Jsont.Object.map ~kind:"open span" (fun lane reason start -> { lane; reason; start })
    |> Jsont.Object.mem "lane" Jsont.int ~enc:(fun (o : open_span) -> o.lane)
    |> Jsont.Object.mem "reason" Event.reason ~enc:(fun (o : open_span) -> o.reason)
    |> Jsont.Object.mem "start" Jsont.int ~enc:(fun (o : open_span) -> o.start)
    |> Jsont.Object.finish

  let snapshot_jsont =
    Codec.record "stalls.snapshot" (fun spans counts open_spans : snapshot ->
        { spans; counts; open_spans })
    |> Jsont.Object.mem "spans" Jsont.int ~enc:(fun (s : snapshot) -> s.spans)
    |> Jsont.Object.mem "counts" (Jsont.list Summary.count) ~enc:(fun (s : snapshot) -> s.counts)
    |> Jsont.Object.mem "open_spans" (Jsont.list open_span) ~enc:(fun (s : snapshot) ->
        s.open_spans)
    |> Jsont.Object.finish
end
