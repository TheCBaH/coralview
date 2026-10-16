[@@@ai_disclosure "ai-generated"]
[@@@ai_model "claude-opus-5-5"]
[@@@ai_provider "Anthropic"]

open Hwfrp

type access = {
  cycle : int;
  bus : [ `Tcm | `External ];
  pc : int;
  addr : int;
  write : bool;
  bytes : int list;
  data : Bits.t;
}

type fault = {
  f_cycle : int;
  f_pc : int;
  f_addr : int;
  f_write : bool;
  request : (int * int) option;
}

let model = "memory"
let needs = [ "lsu" ]

let value a =
  List.fold_left
    (fun (v, k) b -> (v lor (Bits.field_int a.data ~lo:(8 * b) ~width:8 lsl (8 * k)), k + 1))
    (0, 0) a.bytes
  |> fst

let lanes_of_mask m = List.filter (fun b -> (m lsr b) land 1 = 1) (List.init 16 Fun.id)
let word_at addr = List.init 4 (fun k -> (addr land 15) + k) |> List.filter (fun b -> b < 16)

let graph ?(on_fault = ignore) (c : _ Core.t) f =
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
    request `Tcm "io_dbus_"
      ~fire:
        (if l.tcm_ready then Sig.map2 ( && ) (b "io_dbus_valid") (b "io_dbus_ready")
         else b "io_dbus_valid")
  in
  let ext =
    request `External "io_ebus_dbus_"
      ~fire:(Sig.map2 ( && ) (b "io_ebus_dbus_valid") (b "io_ebus_dbus_ready"))
  in
  let rdata = Bind.signal sc "io_dbus_rdata" Bind.bits
  and erdata = Bind.signal sc "io_ebus_dbus_rdata" Bind.bits in
  (* A read's data is on the bus in the cycle after its request. *)
  let complete req ~rdata =
    let open Sig in
    let+ prev = pre ~init:None req and+ now = req and+ rdata = rdata and+ cycle = cycle c.clk in
    let acc (bus, pc, addr, write, wmask, data) cycle =
      {
        cycle;
        bus;
        pc;
        addr;
        write;
        bytes = (if write then lanes_of_mask wmask else word_at addr);
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
  let last_request = Hashtbl.create 64 in
  let fired = Ev.when_ (Sig.const c.clk true) (Sig.map2 (fun a f -> (a, f)) all faults) in
  Ev.subscribe fired (fun (accesses, fault) ->
      List.iter
        (fun a ->
          Hashtbl.replace last_request (a.pc, a.write) (a.cycle, a.addr);
          f a)
        accesses;
      Option.iter
        (fun (cycle, pc, addr, write) ->
          on_fault
            {
              f_cycle = cycle;
              f_pc = pc;
              f_addr = addr;
              f_write = write;
              request = Hashtbl.find_opt last_request (pc, write);
            })
        fault);
  fun _ -> ()

let run ?on_fault p tr f =
  let (Core.Any c) = Core.bind p tr ~model in
  let finish = graph ?on_fault c f in
  finish (Core.run c)
