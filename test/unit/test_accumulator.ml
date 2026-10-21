open Hwfrp
open Coralview

let read file = In_channel.with_open_bin file In_channel.input_all

let platform file =
  match Platform.of_string (read file) with
  | Ok f -> List.hd (Platform.configurations f)
  | Error e -> failwith e

let pull m cfg dir json vcd =
  Analysis.pull m cfg
    (platform (Printf.sprintf "../%s.t/%s" dir json))
    (Trace.of_string (read (Printf.sprintf "../%s.t/%s" dir vcd)))

let line jsont v = Codec.to_line jsont v
let memory = Accumulator.tap (module Memory.Accumulator)

let%expect_test "Memory: the snapshot of all the events is the summary" =
  let p = pull (module Memory) Memory.Config.default "memory" "mem-core.json" "memory.vcd" in
  let acc = Memory.Accumulator.create () in
  let events = List.of_seq (memory acc p.events) in
  Printf.printf "%d events\n%s\n%s\n" (List.length events)
    (line Memory.Summary.jsont (Memory.Accumulator.snapshot acc))
    (line Memory.Summary.jsont (p.summary ()));
  [%expect
    {|
    7 events
    {"type":"memory.summary","reads":3,"writes":2,"pcs":5,"faults":2}
    {"type":"memory.summary","reads":3,"writes":2,"pcs":5,"faults":2} |}]

let%expect_test "Memory: a filtered stream gives the totals of the filtered events" =
  let p = pull (module Memory) Memory.Config.default "memory" "mem-core.json" "memory.vcd" in
  let acc = Memory.Accumulator.create () in
  Seq.iter
    (function
      | Memory.Event.Access { access = { write = false; _ }; _ } as e ->
          Memory.Accumulator.add acc e
      | _ -> ())
    p.events;
  print_endline (line Memory.Summary.jsont (Memory.Accumulator.snapshot acc));
  [%expect {| {"type":"memory.summary","reads":3,"writes":0,"pcs":3,"faults":0} |}]

let%expect_test "tap is lazy, single-use, and a snapshot neither advances nor changes" =
  let p = pull (module Memory) Memory.Config.default "memory" "mem-core.json" "memory.vcd" in
  let events = List.of_seq p.events in
  let acc = Memory.Accumulator.create () in
  let tapped = memory acc (List.to_seq events) in
  let show label =
    Printf.printf "%s: %s\n" label (line Memory.Summary.jsont (Memory.Accumulator.snapshot acc))
  in
  show "built";
  let first = Memory.Accumulator.snapshot acc in
  (match tapped () with
  | Seq.Cons (_, rest) ->
      show "one pulled";
      show "again";
      ignore (Memory.Accumulator.snapshot acc);
      show "after snapshots";
      Seq.iter ignore rest;
      show "all pulled"
  | Nil -> ());
  Printf.printf "first snapshot unchanged: %b\n"
    (first = Memory.Summary.{ reads = 0; writes = 0; pcs = 0; faults = 0 });
  (match Seq.iter ignore tapped with
  | () -> print_endline "second traversal allowed"
  | exception Seq.Forced_twice -> print_endline "second traversal: Forced_twice");
  show "after the second traversal";
  [%expect
    {|
    built: {"type":"memory.summary","reads":0,"writes":0,"pcs":0,"faults":0}
    one pulled: {"type":"memory.summary","reads":0,"writes":1,"pcs":1,"faults":0}
    again: {"type":"memory.summary","reads":0,"writes":1,"pcs":1,"faults":0}
    after snapshots: {"type":"memory.summary","reads":0,"writes":1,"pcs":1,"faults":0}
    all pulled: {"type":"memory.summary","reads":3,"writes":2,"pcs":5,"faults":2}
    first snapshot unchanged: true
    second traversal: Forced_twice
    after the second traversal: {"type":"memory.summary","reads":3,"writes":2,"pcs":5,"faults":2} |}]

let%expect_test "an empty accumulator" =
  print_endline
    (line Memory.Summary.jsont (Memory.Accumulator.snapshot (Memory.Accumulator.create ())));
  print_endline
    (line Tiles.Summary.jsont (Tiles.Accumulator.snapshot (Tiles.Accumulator.create ())));
  print_endline
    (line Stalls.Accumulator.snapshot_jsont
       (Stalls.Accumulator.snapshot (Stalls.Accumulator.create ())));
  [%expect
    {|
    {"type":"memory.summary","reads":0,"writes":0,"pcs":0,"faults":0}
    {"type":"tiles.summary","writes":0,"file":[]}
    {"type":"stalls.snapshot","spans":0,"counts":[],"open_spans":[]} |}]

let%expect_test "Tiles: the snapshot of all the events is the summary" =
  let p = pull (module Tiles) () "tiles" "tile-core.json" "tiles.vcd" in
  let acc = Tiles.Accumulator.create () in
  Seq.iter (Tiles.Accumulator.add acc) p.events;
  let a = line Tiles.Summary.jsont (Tiles.Accumulator.snapshot acc)
  and b = line Tiles.Summary.jsont (p.summary ()) in
  Printf.printf "equal %b\n%s\n" (a = b) a;
  [%expect
    {|
    equal true
    {"type":"tiles.summary","writes":3,"file":[{"tile":1,"sub":2,"data":"11223344"},{"tile":3,"sub":0,"data":"5566ccdd"}]} |}]

let%expect_test "Stalls: closed spans, and the open ones apart" =
  let p = pull (module Stalls) () "stalls" "stall-core.json" "stalls.vcd" in
  let acc = Stalls.Accumulator.create () in
  Seq.iter (Stalls.Accumulator.add acc) p.events;
  let snap = Stalls.Accumulator.snapshot acc in
  let s = p.summary () in
  print_endline (line Stalls.Accumulator.snapshot_jsont snap);
  print_endline (line Stalls.Summary.jsont s);
  let key lane reason = (lane, Stalls.reason_name reason) in
  let closed =
    List.map (fun (c : Stalls.Summary.count) -> (key c.lane c.reason, c.cycles)) snap.counts
  in
  let completed =
    List.fold_left
      (fun acc (o : Stalls.Accumulator.open_span) ->
        let k = key o.lane o.reason and n = s.cycles - o.start in
        (k, n + Option.value (List.assoc_opt k acc) ~default:0) :: List.remove_assoc k acc)
      closed snap.open_spans
  in
  let legacy =
    List.map (fun (c : Stalls.Summary.count) -> (key c.lane c.reason, c.cycles)) s.counts
  in
  Printf.printf "closed + open to the end = summary: %b\n"
    (List.sort compare completed = List.sort compare legacy);
  [%expect
    {|
    {"type":"stalls.snapshot","spans":6,"counts":[{"lane":0,"reason":"dispatched","cycles":2},{"lane":0,"reason":"empty","cycles":1},{"lane":0,"reason":"raw","cycles":2},{"lane":1,"reason":"behind","cycles":2},{"lane":1,"reason":"raw","cycles":1}],"open_spans":[{"lane":0,"reason":"halted","start":5},{"lane":1,"reason":"empty","start":3}]}
    {"type":"stalls.summary","cycles":6,"counts":[{"lane":0,"reason":"dispatched","cycles":2},{"lane":0,"reason":"empty","cycles":1},{"lane":0,"reason":"halted","cycles":1},{"lane":0,"reason":"raw","cycles":2},{"lane":1,"reason":"empty","cycles":3},{"lane":1,"reason":"behind","cycles":2},{"lane":1,"reason":"raw","cycles":1}]}
    closed + open to the end = summary: true |}]

let%expect_test "Axi: the fixture's totals, from its events" =
  let p = pull (module Axi) Axi.Config.default "axi" "axi-core.json" "axi.vcd" in
  let acc = Axi.Accumulator.create () in
  let events = List.of_seq (Accumulator.tap (module Axi.Accumulator) acc p.events) in
  let s = p.summary () and a = Axi.Accumulator.snapshot acc in
  Printf.printf "%d events\n%s\n" (List.length events) (line Axi.Accumulator.snapshot_jsont a);
  let same =
    a.reads = s.reads && a.read_bytes = s.read_bytes && a.writes = s.writes
    && a.write_bytes = s.write_bytes && a.unmatched = s.unmatched && a.read_latency = s.read_latency
    && a.write_latency = s.write_latency && a.incomplete = s.incomplete && a.first = s.first
    && a.sources = s.sources
  in
  Printf.printf "the summary's fields: %b\n" same;
  [%expect
    {|
    6 events
    {"type":"axi.snapshot","reads":3,"read_bytes":32,"writes":2,"write_bytes":8,"unmatched":1,"read_latency":{"n":2,"min":1,"max":3,"sum":4},"write_latency":{"n":2,"min":2,"max":2,"sum":4},"incomplete":1,"first":1,"sources":[{"id":0,"source":"lsu","transactions":4,"bytes":24,"pinned":4,"instances":4,"disagreeing":1},{"id":1,"source":"fetch","transactions":1,"bytes":16,"pinned":1,"instances":0,"disagreeing":0}]}
    the summary's fields: true |}]

let%expect_test "Axi: a snapshot before the end has not seen the incomplete transaction" =
  let p = pull (module Axi) Axi.Config.default "axi" "axi-core.json" "axi.vcd" in
  let acc = Axi.Accumulator.create () in
  Seq.iter
    (fun e ->
      Axi.Accumulator.add acc e;
      let s = Axi.Accumulator.snapshot acc in
      Printf.printf "reads %d writes %d unmatched %d incomplete %d\n" s.reads s.writes s.unmatched
        s.incomplete)
    p.events;
  [%expect
    {|
    reads 1 writes 0 unmatched 0 incomplete 0
    reads 2 writes 0 unmatched 0 incomplete 0
    reads 2 writes 1 unmatched 0 incomplete 0
    reads 2 writes 2 unmatched 0 incomplete 0
    reads 2 writes 2 unmatched 1 incomplete 0
    reads 3 writes 2 unmatched 1 incomplete 1 |}]
