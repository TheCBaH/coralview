[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

let name = "traps"
let doc = "Faults, the CSR updates they cause and whether the handler ran."
let needs = [ "traps"; "dispatch_debug"; "retirement_debug" ]

module IM = Map.Make (Int)

module Config = struct
  type t = unit

  let default = ()
end

type retirement = { at : int; trapped : bool }

type fault = {
  cycle : int;
  source : string;
  pc : int;
  cause : int;
  value : int;
  handler : int;
  csr : int option;
  retired_before : retirement option;
  retired_after : retirement option;
  dispatched : int option;
  delivered : int option;
  until : int;
}

type csr_change = { c_cycle : int; c_mcause : int; c_mepc : int; c_mtval : int }

module Event = struct
  type t = Fault of fault | Csr_change of csr_change

  let retirement =
    Jsont.Object.map ~kind:"retirement" (fun at trapped -> { at; trapped })
    |> Jsont.Object.mem "at" Jsont.int ~enc:(fun r -> r.at)
    |> Jsont.Object.mem "trapped" Jsont.bool ~enc:(fun r -> r.trapped)
    |> Jsont.Object.finish

  let fault =
    Codec.case "traps.fault"
      (fun f -> Fault f)
      (Jsont.Object.map
         (fun
           cycle
           source
           pc
           cause
           value
           handler
           csr
           retired_before
           retired_after
           dispatched
           delivered
           until
         ->
           {
             cycle;
             source;
             pc;
             cause;
             value;
             handler;
             csr;
             retired_before;
             retired_after;
             dispatched;
             delivered;
             until;
           })
      |> Jsont.Object.mem "cycle" Jsont.int ~enc:(fun f -> f.cycle)
      |> Jsont.Object.mem "source" Jsont.string ~enc:(fun f -> f.source)
      |> Jsont.Object.mem "pc" Jsont.int ~enc:(fun f -> f.pc)
      |> Jsont.Object.mem "cause" Jsont.int ~enc:(fun f -> f.cause)
      |> Jsont.Object.mem "value" Jsont.int ~enc:(fun f -> f.value)
      |> Jsont.Object.mem "handler" Jsont.int ~enc:(fun f -> f.handler)
      |> Codec.opt (fun f -> f.csr) "csr" Jsont.int
      |> Codec.opt (fun f -> f.retired_before) "retired_before" retirement
      |> Codec.opt (fun f -> f.retired_after) "retired_after" retirement
      |> Codec.opt (fun f -> f.dispatched) "dispatched" Jsont.int
      |> Codec.opt (fun f -> f.delivered) "delivered" Jsont.int
      |> Jsont.Object.mem "until" Jsont.int ~enc:(fun f -> f.until)
      |> Jsont.Object.finish)

  let csr_change =
    Codec.case "traps.csr_change"
      (fun c -> Csr_change c)
      (Jsont.Object.map (fun c_cycle c_mcause c_mepc c_mtval ->
           { c_cycle; c_mcause; c_mepc; c_mtval })
      |> Jsont.Object.mem "cycle" Jsont.int ~enc:(fun c -> c.c_cycle)
      |> Jsont.Object.mem "mcause" Jsont.int ~enc:(fun c -> c.c_mcause)
      |> Jsont.Object.mem "mepc" Jsont.int ~enc:(fun c -> c.c_mepc)
      |> Jsont.Object.mem "mtval" Jsont.int ~enc:(fun c -> c.c_mtval)
      |> Jsont.Object.finish)

  let jsont =
    Codec.cases "traps.event"
      (function
        | Fault f -> Jsont.Object.Case.value fault f
        | Csr_change c -> Jsont.Object.Case.value csr_change c)
      Jsont.Object.Case.[ make fault; make csr_change ]

  let cycle = function Fault f -> f.cycle | Csr_change c -> c.c_cycle
  let pc = function Fault f -> Some f.pc | Csr_change c -> Some c.c_mepc
end

module Summary = struct
  type t = { cycles : int; faults : int; delivered : int; unmatched : int }

  let jsont =
    Codec.record "traps.summary" (fun cycles faults delivered unmatched ->
        { cycles; faults; delivered; unmatched })
    |> Jsont.Object.mem "cycles" Jsont.int ~enc:(fun s -> s.cycles)
    |> Jsont.Object.mem "faults" Jsont.int ~enc:(fun s -> s.faults)
    |> Jsont.Object.mem "delivered" Jsont.int ~enc:(fun s -> s.delivered)
    |> Jsont.Object.mem "unmatched" Jsont.int ~enc:(fun s -> s.unmatched)
    |> Jsont.Object.finish
end

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

type state = {
  open_ : fault option;  (** The last fault: its record ends at the next one. *)
  last_regs : (int * int * int) option;
  last_retired : retirement IM.t;  (** By PC. *)
  faults : int;
  delivered : int;
  unmatched : int;
}

let rec step s (x : sample) =
  (* A fault asserted in this cycle reaches the CSRs and retirement in later cycles. *)
  let open_ =
    Option.map
      (fun f ->
        let f =
          List.fold_left
            (fun f (pc, trapped) ->
              let f =
                if pc = f.pc && f.retired_after = None then
                  { f with retired_after = Some { at = x.now; trapped } }
                else f
              in
              if pc = f.handler && f.delivered = None then { f with delivered = Some x.now } else f)
            { f with until = x.now } x.retired
        in
        if List.mem f.handler x.dispatched && f.dispatched = None then
          { f with dispatched = Some x.now }
        else f)
      s.open_
  in
  let open_, matched =
    match open_ with
    | Some f when f.csr = None && (f.cause, f.pc, f.value) = x.regs ->
        (Some { f with csr = Some x.now }, true)
    | o -> (o, false)
  in
  let change =
    if (not matched) && s.last_regs <> Some x.regs && s.last_regs <> None then
      let mcause, mepc, mtval = x.regs in
      [ Event.Csr_change { c_cycle = x.now; c_mcause = mcause; c_mepc = mepc; c_mtval = mtval } ]
    else []
  in
  let last_retired =
    List.fold_left
      (fun m (pc, trapped) -> IM.add pc { at = x.now; trapped } m)
      s.last_retired x.retired
  in
  let s =
    {
      s with
      open_;
      last_regs = Some x.regs;
      last_retired;
      unmatched = s.unmatched + List.length change;
    }
  in
  match x.fm with
  | None -> (s, change)
  | Some (source, cause, pc, value) ->
      let f =
        {
          cycle = x.now;
          source;
          pc;
          cause;
          value;
          handler = x.mtvec land lnot 3;
          csr = None;
          retired_before = IM.find_opt pc s.last_retired;
          retired_after = None;
          dispatched = None;
          delivered = None;
          until = x.now;
        }
      in
      let closed, s = close s in
      ({ s with open_ = Some f; faults = s.faults + 1 }, change @ closed)

and close s =
  match s.open_ with
  | None -> ([], s)
  | Some f ->
      ( [ Event.Fault f ],
        { s with open_ = None; delivered = (s.delivered + if f.delivered <> None then 1 else 0) } )

let build () (c : _ Core.t) =
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
  let out, st =
    Machine.run
      {
        name;
        init =
          {
            open_ = None;
            last_regs = None;
            last_retired = IM.empty;
            faults = 0;
            delivered = 0;
            unmatched = 0;
          };
        step = (fun ~tick:_ s x -> step s x);
        finish = (fun s -> fst (close s));
        every_tick = true;
      }
      sample
  in
  let summary (st' : Sched.run_stats) =
    let s = snd (close (Sig.peek st)) in
    {
      Summary.cycles = st'.ticks.(0);
      faults = s.faults;
      delivered = s.delivered;
      unmatched = s.unmatched;
    }
  in
  (out, summary)

let text (ctx : Text.ctx) events (s : Summary.t) =
  let at = function Some c -> Printf.sprintf "at %d" c | None -> "never" in
  let fault f =
    Printf.printf "%8d %s fault: cause %d (%s), pc %08x, mtval %08x\n" f.cycle f.source f.cause
      (cause_name f.cause) f.pc f.value;
    Printf.printf "         csr      mcause/mepc/mtval hold them %s\n" (at f.csr);
    let ret = function
      | Some r -> Printf.sprintf "at %d%s" r.at (if r.trapped then " as a trap" else "")
      | None -> "never"
    in
    Printf.printf "         pc       retired up to the fault %s, after it %s\n"
      (ret f.retired_before) (ret f.retired_after);
    Printf.printf "         handler  %08x dispatched %s, retired %s: %s\n" f.handler
      (at f.dispatched) (at f.delivered)
      (match f.delivered with
      | Some _ -> "delivered"
      | None -> Printf.sprintf "not delivered by cycle %d" f.until)
  and change c =
    Printf.printf "%8d csr change with no fault: mcause %d (%s), mepc %08x, mtval %08x\n" c.c_cycle
      c.c_mcause (cause_name c.c_mcause) c.c_mepc c.c_mtval
  in
  List.filter_map (function Event.Fault f -> Some (f.cycle, fun () -> fault f) | _ -> None) events
  @ List.filter_map
      (function Event.Csr_change c -> Some (c.c_cycle, fun () -> change c) | _ -> None)
      events
  |> List.stable_sort (fun (a, _) (b, _) -> compare a b)
  |> List.iter (fun (_, print) -> print ());
  Printf.printf "root %s: %d cycles, %d faults, %d delivered\n" ctx.root s.cycles s.faults
    s.delivered
