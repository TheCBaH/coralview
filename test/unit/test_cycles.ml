open Hwfrp
open Coralview

let read file = In_channel.with_open_bin file In_channel.input_all

let platform file =
  match Platform.of_string (read file) with
  | Ok f -> List.hd (Platform.configurations f)
  | Error e -> failwith e

(* A core whose clock is the second domain of its net: [decoy] is defined first. *)
let core dir json vcd ~decoy ~model =
  let p = platform (Printf.sprintf "../%s.t/%s" dir json) in
  let tr = Hwfrp_vcd.of_string (read (Printf.sprintf "../%s.t/%s" dir vcd)) in
  let net = Net.create () in
  let (Clock.Any _) =
    Bind.clock net tr ~model ~name:"decoy" After_rising (Platform.scope p decoy)
  in
  let (Clock.Any clk) =
    Bind.clock net tr ~model ~purpose:"core clock" ~name:p.clock p.sample
      (Platform.scope p [ p.clock ])
  in
  Core.Any { Core.net; trace = tr; clk; platform = p; model; deps = Hashtbl.create 4 }

let cycles (type k e s)
    (module A : Analysis.S with type Config.t = k and type Event.t = e and type Summary.t = s)
    (cfg : k) ~dir ~json ~vcd ~decoy (cycles : s -> int) =
  let (Core.Any c) = core dir json vcd ~decoy ~model:A.name in
  let summary = Analysis.subscribe (module A) cfg c ignore in
  let st = Core.run c in
  Printf.printf "%-9s decoy ticks %d, core ticks %d, summary cycles %d\n" A.name st.ticks.(0)
    st.ticks.(1)
    (cycles (summary st))

let%expect_test "Summary.cycles is the core clock's domain, whatever its index" =
  let d = [ "io_debug_dispatch_0_instFire" ] in
  cycles
    (module Registers)
    Registers.Config.default ~dir:"registers" ~json:"reg-core.json" ~vcd:"registers.vcd" ~decoy:d
    (fun s -> s.cycles);
  cycles
    (module Vectors)
    Vectors.Config.default ~dir:"vectors" ~json:"vector-core.json" ~vcd:"vectors.vcd" ~decoy:d
    (fun s -> s.cycles);
  cycles
    (module Ops)
    Ops.Config.default ~dir:"ops" ~json:"ops-core.json" ~vcd:"ops.vcd" ~decoy:d
    (fun s -> s.cycles);
  cycles
    (module Traps)
    Traps.Config.default ~dir:"traps" ~json:"trap-core.json" ~vcd:"traps.vcd" ~decoy:d
    (fun s -> s.cycles);
  cycles
    (module Stalls)
    Stalls.Config.default ~dir:"stalls" ~json:"stall-core.json" ~vcd:"stalls.vcd"
    ~decoy:[ "dispatch"; "io_halted" ]
    (fun s -> s.cycles);
  [%expect
    {|
    registers decoy ticks 1, core ticks 7, summary cycles 7
    vectors   decoy ticks 0, core ticks 7, summary cycles 7
    ops       decoy ticks 2, core ticks 12, summary cycles 12
    traps     decoy ticks 3, core ticks 13, summary cycles 13
    stalls    decoy ticks 1, core ticks 6, summary cycles 6 |}]
