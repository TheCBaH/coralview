(* The examples of doc/hwfrp.md, kept compiling and producing the output shown there. *)
open Hwfrp
module Reference = Vcd_types.Reference

let vcd =
  {|$timescale 1ps $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 1 " io_out_valid $end
$var wire 8 # io_out_bits_data $end
$upscope $end
$enddefinitions $end
#0
$dumpvars
0!
0"
b0 #
$end
#1
1!
#2
0!
1"
b101010 #
#3
1!
#4
0!
0"
#5
1!
#6
0!
#7
1!
#8
0!
1"
b111 #
#9
1!
#10
0!
b1000 #
#11
1!
#12
0!
0"
|}

(* [doc:quick-start] *)
let transfers tr =
  let net = Net.create () in
  let at path = Reference.of_list path in
  let (Clock.Any clk) =
    Bind.clock net tr ~model:"demo" ~name:"clk" After_falling (at [ "top"; "clk" ])
  in
  let scope = Bind.root net tr clk ~model:"demo" (at [ "top" ]) in
  let out = Bundle.valid scope "io_out" in
  let data = Bundle.get out.v_bits "data" Bind.uint in
  let fired = Ev.tag (Sig.cycle clk) (Ev.when_ out.v_valid data) in
  let with_gap =
    Ev.scan ~init:None
      (fun last (d, c) -> (Some c, Some (d, c, Option.map (fun l -> c - l) last)))
      fired
  in
  Ev.subscribe with_gap (fun (d, c, gap) ->
      Printf.printf "cycle %d: %d%s\n" c d
        (match gap with Some g -> Printf.sprintf " (%d cycles after the last)" g | None -> ""));
  let sched = Result.get_ok (Sched.compile net) in
  ignore (Sched.run sched (Sampler.create tr (Net.domains net)))
(* [doc:end] *)

(* [doc:raw] *)
let transfers_raw text =
  let { Vcd.header; simulation } = Vcd.parse_string text in
  let resolver = Vcd.Resolver.make header in
  let id path = Option.get (Vcd.Resolver.find_id resolver (Reference.of_string path)) in
  let clk = id "top.clk" and valid = id "top.io_out_valid" and data = id "top.io_out_bits_data" in
  let values = Hashtbl.create 8 in
  let get i = Hashtbl.find_opt values (Vcd_types.ID.to_string i) in
  let cycle = ref 0 and last = ref None and batch = ref [] in
  let sample () =
    (match (get valid, get data) with
    | Some (Vcd_types.Value.Scalar B1), Some (Int d) ->
        Printf.printf "cycle %d: %d%s\n" !cycle d
          (match !last with
          | Some l -> Printf.sprintf " (%d cycles after the last)" (!cycle - l)
          | None -> "");
        last := Some !cycle
    | _ -> ());
    incr cycle
  in
  (* The changes of one timestamp are applied together; a falling clock edge then samples. *)
  let flush () =
    let before = get clk in
    List.iter (fun (i, v) -> Hashtbl.replace values (Vcd_types.ID.to_string i) v) (List.rev !batch);
    batch := [];
    match (before, get clk) with Some (Scalar B1), Some (Scalar B0) -> sample () | _ -> ()
  in
  Seq.iter
    (function
      | Vcd_ast.Timestamp _ -> flush ()
      | Change (i, v) -> batch := (i, v) :: !batch
      | DumpStart _ | DumpEnd | SimComment _ -> ())
    simulation;
  flush ()
(* [doc:end] *)

(* [doc:pull] *)
let transfers_seq tr =
  let net = Net.create () in
  let at path = Reference.of_list path in
  let (Clock.Any clk) =
    Bind.clock net tr ~model:"demo" ~name:"clk" After_falling (at [ "top"; "clk" ])
  in
  let scope = Bind.root net tr clk ~model:"demo" (at [ "top" ]) in
  let out = Bundle.valid scope "io_out" in
  let data = Bundle.get out.v_bits "data" Bind.uint in
  let port = Port.create (Ev.tag (Sig.cycle clk) (Ev.when_ out.v_valid data)) in
  let sched = Result.get_ok (Sched.compile net) in
  Port.seq (Run.start sched (Sampler.create tr (Net.domains net))) port
(* [doc:end] *)

(* [doc:track] *)
let bursts tr =
  let net = Net.create () in
  let at path = Reference.of_list path in
  let (Clock.Any clk) =
    Bind.clock net tr ~model:"demo" ~name:"clk" After_falling (at [ "top"; "clk" ])
  in
  let scope = Bind.root net tr clk ~model:"demo" (at [ "top" ]) in
  let valid = (Bundle.valid scope "io_out").v_valid in
  let edges = Sig.map2 (fun now before -> (now, before)) valid (Sig.pre ~init:false valid) in
  let ops =
    Ev.filter_map
      (fun ((now, before), c) ->
        match (now, before) with
        | true, false -> Some [ Track.Open ((), { Span.start = c; stop = None }) ]
        | false, true ->
            Some [ Track.Update ((), fun s -> { s with stop = Some (c - 1) }); Close () ]
        | _ -> None)
      (Ev.tag (Sig.cycle clk) (Ev.when_ (Sig.const clk true) edges))
  in
  Ev.subscribe (Track.run ops)
    (List.iter (function Track.Closed s | Open_at_end s | Displaced s ->
        Printf.printf "burst from cycle %d, %s\n" s.Span.start
          (match Span.length s with Some n -> Printf.sprintf "%d cycles" n | None -> "open")));
  ignore (Sched.run (Result.get_ok (Sched.compile net)) (Sampler.create tr (Net.domains net)))
(* [doc:end] *)

(* [doc:stats] *)
let stats tr = Reduce.Stats.of_seq (Seq.map fst (transfers_seq tr))
(* [doc:end] *)

let%expect_test "pull, track, reduce" =
  Seq.iter
    (fun (d, c) -> Printf.printf "%d at cycle %d\n" d c)
    (Seq.take 1 (transfers_seq (Trace.of_string vcd)));
  [%expect {| 42 at cycle 0 |}];
  bursts (Trace.of_string vcd);
  [%expect {|
    burst from cycle 0, 1 cycles
    burst from cycle 3, 2 cycles |}];
  let s = stats (Trace.of_string vcd) in
  Printf.printf "n %d, min %d, max %d, mean %.2f\n" s.n s.min s.max (Reduce.Stats.mean s);
  [%expect {| n 3, min 7, max 42, mean 19.00 |}]

let%expect_test "quick start" =
  transfers (Trace.of_string vcd);
  [%expect
    {|
    cycle 0: 42
    cycle 3: 7 (3 cycles after the last)
    cycle 4: 8 (1 cycles after the last) |}];
  transfers_raw vcd;
  [%expect
    {|
    cycle 0: 42
    cycle 3: 7 (3 cycles after the last)
    cycle 4: 8 (1 cycles after the last) |}]
