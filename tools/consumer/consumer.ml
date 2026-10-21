(* Built against the installed coralview only: the typed events from a line, a snapshot, and the same
   Memory events from an FST file. *)
open Coralview

let axi = (module Axi : Output.OUTPUT with type Event.t = Axi.Event.t)

let () =
  let event = Axi.Event.Unmatched { cycle = 3; write = true; id = 2; what = "response" } in
  let line = Output.encode_event axi event in
  print_endline line;
  (match Output.decode_event axi line with
  | Ok e -> assert (e = event)
  | Error e -> failwith e);
  (match Output.decode_event axi "{" with Ok _ -> failwith "accepted" | Error _ -> ());
  let acc = Axi.Accumulator.create () in
  Seq.iter (Axi.Accumulator.add acc) (Seq.return event);
  Printf.printf "unmatched %d\n" (Axi.Accumulator.snapshot acc).unmatched;
  let platform =
    match Platform.of_string (In_channel.with_open_bin Sys.argv.(1) In_channel.input_all) with
    | Ok f -> List.hd (Platform.configurations f)
    | Error e -> failwith e
  in
  let s = Analysis.events_file (module Memory) Memory.Config.default platform Sys.argv.(2) in
  let acc = Memory.Accumulator.create () in
  let n = Seq.length (Accumulator.tap (module Memory.Accumulator) acc s.events) in
  s.finish ();
  let snap = Memory.Accumulator.snapshot acc in
  Printf.printf "%d memory events: %d reads, %d writes, %d diagnostics\n" n snap.reads snap.writes
    (List.length (s.diags ()))
