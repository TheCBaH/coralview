(* A model's events, summary and diagnostics are the same whether it is built alone or in a net that
   other analyses share: a command reads a trace once, finds the window in the retirements of the run
   that prints the rows, and does not read the rows differently. *)
open Hwfrp
open Coralview

let read path = In_channel.with_open_bin path In_channel.input_all

let platform json =
  match Platform.of_string (read json) with
  | Ok f -> List.hd (Platform.configurations f)
  | Error e -> failwith e

let diags l = List.map (fun (d : Diag.t) -> (d.code, d.cycle, d.message)) l

let alone (type k e s)
    (module A : Analysis.S with type Config.t = k and type Event.t = e and type Summary.t = s) p
    text =
  let pulled = Analysis.pull (module A) A.Config.default p (Hwfrp_vcd.of_string text) in
  let events = List.map (Codec.to_line A.Event.jsont) (List.of_seq pulled.events) in
  (events, Codec.to_line A.Summary.jsont (pulled.summary ()), diags (pulled.diags ()))

(* Twice in one net, which also builds the retirements if the platform has them. *)
let shared (type k e s)
    (module A : Analysis.S with type Config.t = k and type Event.t = e and type Summary.t = s) p
    text ~commits =
  let (first, second, retirements), ds =
    Pass.run p (Hwfrp_vcd.of_string text) ~model:A.name
      {
        build =
          (fun c ->
            let retirements = if commits then Some (Pass.commits c) else None in
            let first = Pass.collect (module A) A.Config.default c in
            let second = Pass.collect (module A) A.Config.default c in
            fun stats -> (first stats, second stats, Option.map (fun r -> r stats) retirements));
      }
  in
  let line (events, summary) =
    (List.map (Codec.to_line A.Event.jsont) events, Codec.to_line A.Summary.jsont summary)
  in
  (line first, line second, retirements, diags ds)

let retirements_alone p text =
  let pulled = Analysis.pull (module Commits) () p (Hwfrp_vcd.of_string text) in
  Commits.commits (List.of_seq pulled.events)

let same m json vcd ~commits =
  let p = platform json and text = read vcd in
  let events, summary, ds = alone m p text in
  let first, second, retirements, ds' = shared m p text ~commits in
  events <> []
  && first = (events, summary)
  && second = first && ds = ds'
  && retirements = if commits then Some (retirements_alone p text) else None

let%test "memory, with the retirements" =
  same (module Memory) "../cost.t/cost-core.json" "../cost.t/cost.vcd" ~commits:true

let%test "axi, with the retirements" =
  same (module Axi) "../axi.t/axi-core.json" "../axi.t/axi.vcd" ~commits:true

let%test "registers, with the retirements" =
  same
    (module Registers)
    "../registers.t/reg-core.json" "../registers.t/registers.vcd" ~commits:true

let%test "vectors, with the retirements" =
  same (module Vectors) "../vectors.t/vector-core.json" "../vectors.t/vectors.vcd" ~commits:true

let%test "commits" =
  same (module Commits) "../loops.t/loop-core.json" "../loops.t/loop.vcd" ~commits:true

let%test "stalls" =
  same (module Stalls) "../stalls.t/stall-core.json" "../stalls.t/stalls.vcd" ~commits:false

let%test "ops" = same (module Ops) "../ops.t/ops-core.json" "../ops.t/ops.vcd" ~commits:false

let%test "tiles" =
  same (module Tiles) "../tiles.t/tile-core.json" "../tiles.t/tiles.vcd" ~commits:false

let%test "dma" = same (module Dma) "../dma.t/dma-sub.json" "../dma.t/dma.vcd" ~commits:false

let%test "traps" =
  same (module Traps) "../traps.t/trap-core.json" "../traps.t/traps.vcd" ~commits:false
