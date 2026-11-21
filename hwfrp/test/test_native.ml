(* The same waveform as VCD text, a VCD file, a VCD stream and an FST file gives the same samples. *)
open Hwfrp

let clock = [ "TOP"; "core"; "io_aclk" ]
let addr = [ "TOP"; "core"; "lsu"; "io_dbus_addr" ]

let samples tr =
  let c = Option.get (Trace.find tr clock) and a = Option.get (Trace.find tr addr) in
  let s =
    Sampler.create tr
      [| { Trace.clock = c.slot; rule = After_falling; enable = None; reset = None } |]
  in
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

let missing = "data/absent.fst"

let%test "a missing file is a Vcd.Error.E, not a Sys_error" =
  match Hwfrp_native.open_file missing with exception Vcd.Error.E (`Io _) -> true | _ -> false

let%test "open_file_result returns a missing file as an Io error" =
  (match Hwfrp_native.open_file_result missing with Error (`Io _) -> true | _ -> false)
  && Result.is_ok (Hwfrp_native.open_file_result "data/memory.fst")

let%test "a damaged file is a Vcd.Error.E" =
  match Hwfrp_native.open_string "$var" with exception Vcd.Error.E _ -> true | _ -> false

let temp_file text =
  let path = Filename.temp_file "hwfrp" ".vcd" in
  Out_channel.with_open_bin path (fun oc -> output_string oc text);
  path

let drain tr = Seq.iter ignore (Trace.events tr)

let incomplete text =
  let path = temp_file text in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      match drain (Hwfrp_native.open_file path) with
      | exception Vcd.Error.E (`Incomplete _) -> true
      | (exception _) | () -> false)

let%test "a VCD file without its final newline is incomplete, as a stream is" =
  let text = read "data/memory.vcd" in
  incomplete (String.sub text 0 (String.length text - 1))

let%test "a VCD file with an open $dumpvars is incomplete" =
  incomplete
    "$timescale 1ps $end\n\
     $scope module t $end\n\
     $var wire 1 ! c $end\n\
     $upscope $end\n\
     $enddefinitions $end\n\
     #0\n\
     $dumpvars\n\
     0!\n"

let open_fds () = Array.length (Sys.readdir "/proc/self/fd")

let%test "reading a VCD file to its end closes it" =
  let before = open_fds () in
  drain (Hwfrp_native.open_file "data/memory.vcd");
  open_fds () = before

let first_event tr = ignore (Seq.uncons (Trace.events tr))

let%test "with_file closes a file that is not read to its end, VCD and FST" =
  let before = open_fds () in
  List.iter
    (fun path -> Hwfrp_native.with_file path first_event)
    [ "data/memory.vcd"; "data/memory.fst" ];
  (match Hwfrp_native.with_file "data/memory.vcd" (fun _ -> failwith "stop") with
  | exception Failure _ -> ()
  | () -> ());
  open_fds () = before

let%test "close releases a trace that was never read, and is idempotent" =
  let before = open_fds () in
  let tr = Hwfrp_native.open_file "data/memory.vcd" in
  let during = open_fds () in
  Hwfrp_native.close tr;
  Hwfrp_native.close tr;
  during = before + 1 && open_fds () = before

let%test "a strict error names the file" =
  let path = temp_file "$enddefinitions" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      match Hwfrp_native.open_file path with
      | exception Vcd.Error.E (`Incomplete ({ Vcd.Error.file; _ }, _) | `Syntax ({ file; _ }, _)) ->
          file = path
      | _ -> false)

let%test "with_parse_file reads the raw events and closes" =
  let before = open_fds () in
  let n =
    Hwfrp_native.with_parse_file "data/memory.vcd" (fun r ->
        Seq.fold_left (fun n _ -> n + 1) 0 r.simulation)
  in
  n > 4 && open_fds () = before
