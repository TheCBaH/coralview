(* Every analysis fixture gives the same events, diagnostics and summary from its VCD text and from
   the same catalog and value changes held in memory. *)
open Hwfrp
open Coralview

let read path = In_channel.with_open_bin path In_channel.input_all

let platform json =
  match Platform.of_string (read json) with
  | Ok f -> List.hd (Platform.configurations f)
  | Error e -> failwith e

(* The text's catalog and events, as a producer in memory would hand them over. *)
let from_memory text =
  let { Vcd.header; simulation } = Vcd.parse_string text in
  In_memory.trace header (List.to_seq (List.of_seq simulation))

let run (type k e s)
    (module A : Analysis.S with type Config.t = k and type Event.t = e and type Summary.t = s) json
    trace =
  let s = Analysis.stream (module A) A.Config.default (platform json) trace in
  let events = List.map (Codec.to_line A.Event.jsont) (List.of_seq s.events) in
  let diags = List.map (fun (d : Diag.t) -> (d.code, d.cycle, d.message)) (s.diags ()) in
  (events, diags, Codec.to_line A.Summary.jsont (s.summary ()))

let same m json vcd =
  let text = read vcd in
  let ((events, _, _) as want) = run m json (Hwfrp_vcd.of_string text) in
  events <> [] && want = run m json (from_memory text)

let%test "memory" = same (module Memory) "../memory.t/mem-core.json" "../memory.t/memory.vcd"
let%test "axi" = same (module Axi) "../axi.t/axi-core.json" "../axi.t/axi.vcd"

let%test "registers" =
  same (module Registers) "../registers.t/reg-core.json" "../registers.t/registers.vcd"

let%test "tiles" = same (module Tiles) "../tiles.t/tile-core.json" "../tiles.t/tiles.vcd"
let%test "stalls" = same (module Stalls) "../stalls.t/stall-core.json" "../stalls.t/stalls.vcd"

(* The same, fed [batch] events at a time and paused after every occurrence. *)
let live (type k e s)
    (module A : Analysis.S with type Config.t = k and type Event.t = e and type Summary.t = s) json
    text batch =
  let { Vcd.header; simulation } = Vcd.parse_string text in
  let evs = Array.of_seq simulation in
  let src = In_memory.Live.create header in
  let (Core.Any c) = Core.bind (platform json) (In_memory.Live.trace src) ~model:A.name in
  let ev, summary = A.build A.Config.default c in
  let port = Port.create ev in
  let run = Core.start c in
  let got = ref [] in
  let rec drain () =
    match Port.poll run port with
    | Port.Item l ->
        List.iter (fun x -> got := Codec.to_line A.Event.jsont x :: !got) l;
        Run.pause run;
        if Port.pending port = 0 then assert (List.mem (Port.poll run port) [ Port.Paused; Ended ]);
        Run.resume run;
        drain ()
    | Starved | Ended -> ()
    | Paused -> failwith "unexpected pause"
  in
  let i = ref 0 in
  while !i < Array.length evs do
    for _ = 1 to min batch (Array.length evs - !i) do
      In_memory.Live.push src evs.(!i);
      incr i
    done;
    if !i = Array.length evs then In_memory.Live.finish src;
    drain ()
  done;
  let summary = Codec.to_line A.Summary.jsont (summary (Run.finish run)) in
  let diags =
    List.map (fun (d : Diag.t) -> (d.code, d.cycle, d.message)) (List.of_seq (Diag.stream c.net))
  in
  (List.rev !got, diags, summary)

let batches m json vcd =
  let text = read vcd in
  let want = run m json (Hwfrp_vcd.of_string text) in
  List.for_all (fun batch -> live m json text batch = want) [ 1; 7; 100; 100000 ]

let%test "memory, fed in pieces" =
  batches (module Memory) "../memory.t/mem-core.json" "../memory.t/memory.vcd"

let%test "axi, fed in pieces" = batches (module Axi) "../axi.t/axi-core.json" "../axi.t/axi.vcd"

let%test "stalls, fed in pieces" =
  batches (module Stalls) "../stalls.t/stall-core.json" "../stalls.t/stalls.vcd"
