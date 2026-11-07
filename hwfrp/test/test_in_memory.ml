(* A trace built from values gives the samples of the VCD text with the same content. *)
open Hwfrp
open Vcd_types

let text =
  {|$timescale 1ps $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 8 " d $end
$upscope $end
$enddefinitions $end
#0
$dumpvars
0!
b0 "
$end
#1
1!
#2
0!
b101 "
#3
1!
#4
0!
b1111 "
|}

let samples tr =
  let c = Option.get (Trace.track_path tr "top.clk")
  and d = Option.get (Trace.track_path tr "top.d") in
  let s = Sampler.create tr [| { Trace.clock = c.slot; rule = After_falling; enable = None } |] in
  let rec go acc =
    match Sampler.next s with
    | None -> List.rev acc
    | Some (tick : Trace.tick) ->
        go ((tick.index, Timestamp.to_int64 tick.time, Sampler.value s d.slot) :: acc)
  in
  go []

let%test "a catalog and events built by hand" =
  let open In_memory in
  let header = header [ scope "top" [ var ~id:"!" ~width:1 "clk"; var ~id:"\"" ~width:8 "d" ] ] in
  let bit b = Value.Scalar (if b then B1 else B0) in
  let events =
    List.to_seq
      [
        at 0L;
        change ~id:"!" (bit false);
        change ~id:"\"" (Value.Int 0);
        at 1L;
        change ~id:"!" (bit true);
        at 2L;
        change ~id:"!" (bit false);
        change ~id:"\"" (Value.Int 5);
        at 3L;
        change ~id:"!" (bit true);
        at 4L;
        change ~id:"!" (bit false);
        change ~id:"\"" (Value.Int 15);
      ]
  in
  let got = samples (trace header events) in
  List.length got = 2 && got = samples (Hwfrp_vcd.of_string text)

let%test "the events of a parsed file, replayed from memory" =
  let { Vcd.header; simulation } = Vcd.parse_string text in
  let events = List.of_seq simulation in
  samples (In_memory.trace header (List.to_seq events)) = samples (Hwfrp_vcd.of_string text)
