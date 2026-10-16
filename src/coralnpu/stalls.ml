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

type lane = { lane : int; pc : int; word : int; reason : reason }

let model = "stalls"
let needs = [ "dispatch" ]

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

let graph (c : _ Core.t) f =
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
  let cycle = Sig.cycle c.clk in
  Ev.subscribe
    (Ev.when_ (Sig.const c.clk true) (Sig.map2 (fun n l -> (n, l)) cycle lanes))
    (fun (n, l) -> f n l);
  fun (st : Sched.run_stats) -> st.ticks.(0)

let run p tr f =
  let (Core.Any c) = Core.bind p tr ~model in
  let finish = graph c f in
  finish (Core.run c)
