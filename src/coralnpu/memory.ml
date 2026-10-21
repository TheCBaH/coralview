[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

let name = "memory"
let doc = "LSU data requests and faults, with PC, address and data."
let needs = [ "lsu" ]

module IM = Map.Make (Int)

module RM = Map.Make (struct
  type t = int * bool

  let compare = compare
end)

module Config = struct
  type t = { region : Region.t }

  let default = { region = Region.none }
end

module Event = struct
  type bus = Tcm | External

  type access = {
    cycle : int;  (** Of the request. *)
    bus : bus;
    pc : int;
    access : Access.t;  (** [bytes]: the lanes selected. *)
    lanes : int list;
    data : Bits.t;
  }

  type fault = {
    cycle : int;
    pc : int;
    address : int;
    write : bool;
    region : string option;
    request : (int * int) option;
  }

  type t = Access of access | Fault of fault

  let bus = Jsont.enum ~kind:"bus" [ ("tcm", Tcm); ("external", External) ]

  let access =
    Codec.case "memory.access"
      (fun a -> Access a)
      (Jsont.Object.map (fun cycle bus pc access lanes data ->
           { cycle; bus; pc; access; lanes; data })
      |> Jsont.Object.mem "cycle" Jsont.int ~enc:(fun (a : access) -> a.cycle)
      |> Jsont.Object.mem "bus" bus ~enc:(fun a -> a.bus)
      |> Jsont.Object.mem "pc" Jsont.int ~enc:(fun (a : access) -> a.pc)
      |> Jsont.Object.mem "access" Access.jsont ~enc:(fun a -> a.access)
      |> Jsont.Object.mem "lanes" Jsont.(list int) ~enc:(fun a -> a.lanes)
      |> Jsont.Object.mem "data" Codec.bits ~enc:(fun a -> a.data)
      |> Jsont.Object.finish)

  let request =
    Jsont.Object.map ~kind:"request" (fun cycle address -> (cycle, address))
    |> Jsont.Object.mem "cycle" Jsont.int ~enc:fst
    |> Jsont.Object.mem "address" Jsont.int ~enc:snd
    |> Jsont.Object.finish

  let fault =
    Codec.case "memory.fault"
      (fun f -> Fault f)
      (Jsont.Object.map (fun cycle pc address write region request ->
           { cycle; pc; address; write; region; request })
      |> Jsont.Object.mem "cycle" Jsont.int ~enc:(fun (f : fault) -> f.cycle)
      |> Jsont.Object.mem "pc" Jsont.int ~enc:(fun (f : fault) -> f.pc)
      |> Jsont.Object.mem "address" Jsont.int ~enc:(fun f -> f.address)
      |> Jsont.Object.mem "write" Jsont.bool ~enc:(fun f -> f.write)
      |> Codec.opt (fun f -> f.region) "region" Jsont.string
      |> Codec.opt (fun f -> f.request) "request" request
      |> Jsont.Object.finish)

  let jsont =
    Codec.cases "memory.event"
      (function
        | Access a -> Jsont.Object.Case.value access a | Fault f -> Jsont.Object.Case.value fault f)
      Jsont.Object.Case.[ make access; make fault ]

  let cycle = function Access a -> a.cycle | Fault f -> f.cycle
  let pc = function Access a -> Some a.pc | Fault f -> Some f.pc
end

module Summary = struct
  type t = { reads : int; writes : int; pcs : int; faults : int }

  let jsont =
    Codec.record "memory.summary" (fun reads writes pcs faults -> { reads; writes; pcs; faults })
    |> Jsont.Object.mem "reads" Jsont.int ~enc:(fun s -> s.reads)
    |> Jsont.Object.mem "writes" Jsont.int ~enc:(fun s -> s.writes)
    |> Jsont.Object.mem "pcs" Jsont.int ~enc:(fun s -> s.pcs)
    |> Jsont.Object.mem "faults" Jsont.int ~enc:(fun s -> s.faults)
    |> Jsont.Object.finish
end

let value (a : Event.access) =
  List.fold_left
    (fun (v, k) b -> (v lor (Bits.field_int a.data ~lo:(8 * b) ~width:8 lsl (8 * k)), k + 1))
    (0, 0) a.lanes
  |> fst

let lanes_of_mask m = List.filter (fun b -> (m lsr b) land 1 = 1) (List.init 16 Fun.id)
let word_at addr = List.init 4 (fun k -> (addr land 15) + k) |> List.filter (fun b -> b < 16)

type state = {
  last_request : (int * int) RM.t;  (** By PC and direction: cycle and address. *)
  reads : int;
  writes : int;
  pcs : unit IM.t;
  faults : int;
}

let step ~region s (accesses, fault) =
  let s =
    List.fold_left
      (fun s (a : Event.access) ->
        {
          s with
          last_request = RM.add (a.pc, a.access.write) (a.cycle, a.access.address) s.last_request;
          reads = (s.reads + if a.access.write then 0 else 1);
          writes = (s.writes + if a.access.write then 1 else 0);
          pcs = IM.add a.pc () s.pcs;
        })
      s accesses
  in
  let out = List.map (fun a -> Event.Access a) accesses in
  match fault with
  | None -> (s, out)
  | Some (cycle, pc, address, write) ->
      ( { s with faults = s.faults + 1 },
        out
        @ [
            Event.Fault
              {
                cycle;
                pc;
                address;
                write;
                region = Region.find region address;
                request = RM.find_opt (pc, write) s.last_request;
              };
          ] )

let build (cfg : Config.t) (c : _ Core.t) =
  let l = Core.block c "lsu" c.platform.blocks.lsu in
  let sc = Core.scope c l.lsu_scope in
  let b n = Bind.signal sc n Bind.bool and u n = Bind.signal sc n Bind.uint in
  let pc = u "io_ebus_dbus_pc" in
  let request bus prefix ~fire =
    let open Sig in
    let+ fire = fire
    and+ pc = pc
    and+ addr = u (prefix ^ "addr")
    and+ write = b (prefix ^ "write")
    and+ wmask = u (prefix ^ "wmask")
    and+ wdata = Bind.signal sc (prefix ^ "wdata") Bind.bits in
    if fire then Some (bus, pc, addr, write, wmask, wdata) else None
  in
  let tcm =
    request Event.Tcm "io_dbus_"
      ~fire:
        (if l.tcm_ready then Sig.map2 ( && ) (b "io_dbus_valid") (b "io_dbus_ready")
         else b "io_dbus_valid")
  in
  let ext =
    request Event.External "io_ebus_dbus_"
      ~fire:(Sig.map2 ( && ) (b "io_ebus_dbus_valid") (b "io_ebus_dbus_ready"))
  in
  let rdata = Bind.signal sc "io_dbus_rdata" Bind.bits
  and erdata = Bind.signal sc "io_ebus_dbus_rdata" Bind.bits in
  (* A read's data is on the bus in the cycle after its request. *)
  let complete req ~rdata =
    let open Sig in
    let+ prev = pre ~init:None req and+ now = req and+ rdata = rdata and+ cycle = cycle c.clk in
    let acc (bus, pc, address, write, wmask, data) cycle =
      let lanes = if write then lanes_of_mask wmask else word_at address in
      {
        Event.cycle;
        bus;
        pc;
        access =
          { address; bytes = List.length lanes; write; region = Region.find cfg.region address };
        lanes;
        data;
      }
    in
    let writes = match now with Some ((_, _, _, true, _, _) as r) -> [ acc r cycle ] | _ -> [] in
    let reads =
      match prev with
      | Some (bus, pc, addr, false, wmask, _) ->
          [ acc (bus, pc, addr, false, wmask, rdata) (cycle - 1) ]
      | _ -> []
    in
    reads @ writes
  in
  let all = Sig.map2 ( @ ) (complete tcm ~rdata) (complete ext ~rdata:erdata) in
  let faults =
    let open Sig in
    let+ valid = b "io_fault_valid"
    and+ write = b "io_fault_bits_write"
    and+ addr = u "io_fault_bits_addr"
    and+ epc = u "io_fault_bits_epc"
    and+ cycle = cycle c.clk in
    if valid then Some (cycle, epc, addr, write) else None
  in
  let out, st =
    Machine.run
      {
        name;
        init = { last_request = RM.empty; reads = 0; writes = 0; pcs = IM.empty; faults = 0 };
        step = (fun ~tick:_ s x -> step ~region:cfg.region s x);
        finish = (fun _ -> []);
        every_tick = true;
      }
      (Sig.map2 (fun a f -> (a, f)) all faults)
  in
  let summary _ =
    let s = Sig.peek st in
    { Summary.reads = s.reads; writes = s.writes; pcs = IM.cardinal s.pcs; faults = s.faults }
  in
  (out, summary)

let text (ctx : Text.ctx) events (s : Summary.t) =
  let region = Region.suffix ctx.region in
  let shown = ref 0 in
  List.iter
    (function
      | Event.Fault f ->
          if Text.selected ctx.window ~cycle:f.cycle ~pc:f.pc then
            Printf.printf "%8d fault %s pc %08x addr %08x%s, %s\n" f.cycle
              (if f.write then "W" else "R")
              f.pc f.address (region f.address)
              (match f.request with
              | Some (cycle, addr) -> Printf.sprintf "requested at %d, addr %08x" cycle addr
              | None -> "no request seen")
      | Access a ->
          if Text.selected ctx.window ~cycle:a.cycle ~pc:a.pc && !shown < ctx.limit then begin
            incr shown;
            Printf.printf "%8d %s %s pc %08x addr %08x%s %d bytes %0*x\n" a.cycle
              (match a.bus with Tcm -> "tcm" | External -> "ext")
              (if a.access.write then "W" else "R")
              a.pc a.access.address (region a.access.address) (List.length a.lanes)
              (2 * List.length a.lanes)
              (value a)
          end)
    events;
  Printf.printf "root %s: %d read and %d write requests from %d PCs, %d faults\n" ctx.root s.reads
    s.writes s.pcs s.faults

module Accumulator = struct
  type event = Event.t
  type snapshot = Summary.t

  type t = {
    mutable reads : int;
    mutable writes : int;
    mutable pcs : unit IM.t;
    mutable faults : int;
  }

  let create () = { reads = 0; writes = 0; pcs = IM.empty; faults = 0 }

  let add t = function
    | Event.Access a ->
        if a.access.write then t.writes <- t.writes + 1 else t.reads <- t.reads + 1;
        t.pcs <- IM.add a.pc () t.pcs
    | Event.Fault _ -> t.faults <- t.faults + 1

  let snapshot t =
    { Summary.reads = t.reads; writes = t.writes; pcs = IM.cardinal t.pcs; faults = t.faults }
end
