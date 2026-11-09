(* The same waveform as VCD text, a VCD file, a VCD stream and an FST file gives the same samples. *)
open Hwfrp

let clock = [ "TOP"; "core"; "io_aclk" ]
let addr = [ "TOP"; "core"; "lsu"; "io_dbus_addr" ]

let samples tr =
  let c = Option.get (Trace.find tr clock) and a = Option.get (Trace.find tr addr) in
  let s = Sampler.create tr [| { Trace.clock = c.slot; rule = After_falling; enable = None } |] in
  let rec go acc =
    match Sampler.next s with
    | None -> List.rev acc
    | Some (tick : Trace.tick) ->
        go ((tick.index, Vcd_types.Timestamp.to_int64 tick.time, Sampler.value s a.slot) :: acc)
  in
  go []

let read path = In_channel.with_open_bin path In_channel.input_all

let%test "VCD and FST, as text, file and stream, give the same samples" =
  let text = read "data/memory.vcd" in
  let want = samples (Hwfrp_vcd.of_string text) in
  List.length want > 4
  && samples (Hwfrp_native.open_file "data/memory.vcd") = want
  && samples (Hwfrp_native.open_file "data/memory.fst") = want
  && samples (Hwfrp_native.open_string (read "data/memory.fst")) = want
  && samples (Hwfrp_native.open_string text) = want
  && In_channel.with_open_bin "data/memory.vcd" (fun ic -> samples (Hwfrp_vcd.of_channel ic)) = want

let%test "the format follows the content" =
  Trace.format (Hwfrp_native.open_file "data/memory.vcd") = `Vcd
  && Trace.format (Hwfrp_native.open_file "data/memory.fst") = `Fst
  && Trace.format (Hwfrp_vcd.of_string (read "data/memory.vcd")) = `Vcd

let%test "a missing file is a Sys_error" =
  match Hwfrp_native.open_file "data/absent.fst" with exception Sys_error _ -> true | _ -> false

let%test "open_file_result turns a missing file into a message" =
  Result.is_error (Hwfrp_native.open_file_result "data/absent.fst")
  && Result.is_ok (Hwfrp_native.open_file_result "data/memory.fst")
