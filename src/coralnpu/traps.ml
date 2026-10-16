[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type retirement = { at : int; trapped : bool }

type fault = {
  cycle : int;
  source : string;
  pc : int;
  cause : int;
  value : int;
  handler : int;
  mutable csr : int option;
  mutable retired_before : retirement option;
  mutable retired_after : retirement option;
  mutable dispatched : int option;
  mutable delivered : int option;
  mutable until : int;
}

type csr_change = { c_cycle : int; c_mcause : int; c_mepc : int; c_mtval : int }
type summary = { cycles : int; faults : fault list; unmatched : csr_change list }

let model = "traps"
let needs = [ "traps"; "dispatch_debug"; "retirement_debug" ]

let cause_name c =
  if c land (1 lsl 31) <> 0 then Printf.sprintf "interrupt %d" (c land 0x7fffffff)
  else
    match c with
    | 0 -> "instruction address misaligned"
    | 1 -> "instruction access fault"
    | 2 -> "illegal instruction"
    | 3 -> "breakpoint"
    | 4 -> "load address misaligned"
    | 5 -> "load access fault"
    | 6 -> "store address misaligned"
    | 7 -> "store access fault"
    | 8 | 9 | 11 -> "environment call"
    | c -> Printf.sprintf "cause %d" c

type sample = {
  now : int;
  fm : (string * int * int * int) option;  (** Source, cause, PC, value. *)
  regs : int * int * int;  (** mcause, mepc, mtval. *)
  mtvec : int;
  dispatched : int list;
  retired : (int * bool) list;
}

let graph (c : _ Core.t) =
  let t = Core.block c "traps" c.platform.blocks.traps in
  let fm = Core.scope c t.t_scope and cs = Core.scope c t.csr.csr_scope in
  let bit sc name purpose = Bind.signal sc name Bind.bool ~purpose
  and word sc name purpose = Bind.signal sc name Bind.uint ~purpose in
  let rvv =
    match t.rvv with Some n -> bit fm n "vector core fault" | None -> Sig.const c.clk false
  in
  let fault =
    let open Sig in
    let+ valid = bit fm t.valid "fault asserted"
    and+ cause = word fm t.mcause "fault cause"
    and+ pc = word fm t.mepc "faulting PC"
    and+ value = word fm t.mtval "fault value"
    and+ decode = bit fm t.decode "decode fault"
    and+ memory = bit fm t.memory "LSU fault"
    and+ write = bit fm t.memory_write "LSU fault on a store"
    and+ fetch = bit fm t.fetch "fetch fault"
    and+ rvv = rvv in
    if not valid then None
    else
      let source =
        if memory then if write then "store" else "load"
        else if fetch then "fetch"
        else if rvv then "rvv"
        else if decode then "decode"
        else "other"
      in
      Some (source, cause, pc, value)
  in
  let regs =
    let open Sig in
    let+ mcause = word cs t.csr.csr_mcause "mcause"
    and+ mepc = word cs t.csr.csr_mepc "mepc"
    and+ mtval = word cs t.csr.csr_mtval "mtval" in
    (mcause, mepc, mtval)
  in
  let sample =
    let open Sig in
    let+ now = cycle c.clk
    and+ fm = fault
    and+ regs = regs
    and+ mtvec = word cs t.csr.csr_mtvec "mtvec"
    and+ dispatched =
      Sig.map (List.map (fun (d : Core.dispatched) -> d.d_pc)) (Core.present c (Core.dispatch c))
    and+ retired =
      Sig.map
        (List.map (fun (r : Core.retired) -> (r.r_pc, r.r_trap)))
        (Core.present c (Core.retire c))
    in
    { now; fm; regs; mtvec; dispatched; retired }
  in
  let faults = ref [] and unmatched = ref [] in
  let last_retired = Hashtbl.create 1024 in
  let open_fault = ref None in
  let last_regs = ref None in
  Ev.subscribe
    (Ev.when_ (Sig.const c.clk true) sample)
    (fun s ->
      (* A fault asserted in this cycle reaches the CSRs and retirement in later cycles. *)
      (match !open_fault with
      | None -> ()
      | Some f ->
          f.until <- s.now;
          List.iter
            (fun (pc, trapped) ->
              if pc = f.pc && f.retired_after = None then
                f.retired_after <- Some { at = s.now; trapped };
              if pc = f.handler && f.delivered = None then f.delivered <- Some s.now)
            s.retired;
          if List.mem f.handler s.dispatched && f.dispatched = None then f.dispatched <- Some s.now);
      let matched =
        match !open_fault with
        | Some f when f.csr = None && (f.cause, f.pc, f.value) = s.regs ->
            f.csr <- Some s.now;
            true
        | _ -> false
      in
      (if (not matched) && !last_regs <> Some s.regs && !last_regs <> None then
         let mcause, mepc, mtval = s.regs in
         unmatched :=
           { c_cycle = s.now; c_mcause = mcause; c_mepc = mepc; c_mtval = mtval } :: !unmatched);
      last_regs := Some s.regs;
      List.iter
        (fun (pc, trapped) -> Hashtbl.replace last_retired pc { at = s.now; trapped })
        s.retired;
      match s.fm with
      | None -> ()
      | Some (source, cause, pc, value) ->
          let f =
            {
              cycle = s.now;
              source;
              pc;
              cause;
              value;
              handler = s.mtvec land lnot 3;
              csr = None;
              retired_before = Hashtbl.find_opt last_retired pc;
              retired_after = None;
              dispatched = None;
              delivered = None;
              until = s.now;
            }
          in
          faults := f :: !faults;
          open_fault := Some f);
  fun (st : Sched.run_stats) ->
    { cycles = st.ticks.(0); faults = List.rev !faults; unmatched = List.rev !unmatched }

let run p tr =
  let (Core.Any c) = Core.bind p tr ~model in
  let finish = graph c in
  finish (Core.run c)
