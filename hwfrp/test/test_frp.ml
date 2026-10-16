open Hwfrp
open Vcd_types

(* clk rises at odd timestamps and falls at even ones; data changes with both edges. *)
let vcd =
  {|$timescale 1ps $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 8 " data $end
$var wire 1 # en $end
$var wire 1 $ unused $end
$upscope $end
$enddefinitions $end
#0
$dumpvars
0!
b0 "
1#
0$
$end
#1
1!
b1 "
#2
0!
#3
1!
b10 "
#4
0!
b11 "
0#
1$
#5
1!
#6
0!
b111 "
#7
1!
#8
0!
|}

let sample rule =
  let tr = Trace.of_string vcd in
  let clk = Option.get (Trace.track_path tr "top.clk") in
  let data = Option.get (Trace.track_path tr "top.data") in
  let en = Option.get (Trace.track_path tr "top.en") in
  let s = Sampler.create tr [| { Trace.clock = clk.slot; rule; enable = Some en.slot } |] in
  let rec go () =
    match Sampler.next s with
    | None ->
        let st = Sampler.stats s in
        Printf.printf "events=%d seen=%d tracked=%d timestamps=%d\n" st.events st.changes_seen
          st.changes_tracked st.timestamps
    | Some tk ->
        Format.printf "#%a cycle %d en=%b data=%s changed=[%s]@." Timestamp.pp tk.time tk.index
          tk.enabled
          (Logic.to_string (Sampler.logic s data.slot))
          (String.concat "," (List.map string_of_int (Bitset.elements (Sampler.changed s))));
        go ()
  in
  go ()

let%expect_test "after falling" =
  sample Trace.After_falling;
  [%expect
    {|
    #2 cycle 0 en=true data=00000001 changed=[0,1,2]
    #4 cycle 1 en=false data=00000011 changed=[1,2]
    #6 cycle 2 en=false data=00000111 changed=[1]
    #8 cycle 3 en=false data=00000111 changed=[]
    events=29 seen=18 tracked=16 timestamps=9 |}]

let%expect_test "before rising" =
  sample Trace.Before_rising;
  [%expect
    {|
    #1 cycle 0 en=true data=00000000 changed=[0,1,2]
    #3 cycle 1 en=true data=00000001 changed=[1]
    #5 cycle 2 en=false data=00000011 changed=[1,2]
    #7 cycle 3 en=false data=00000111 changed=[1]
    events=29 seen=18 tracked=16 timestamps=9 |}]

let%expect_test "after rising" =
  sample Trace.After_rising;
  [%expect
    {|
    #1 cycle 0 en=true data=00000001 changed=[0,1,2]
    #3 cycle 1 en=true data=00000010 changed=[1]
    #5 cycle 2 en=false data=00000011 changed=[1,2]
    #7 cycle 3 en=false data=00000111 changed=[1]
    events=29 seen=18 tracked=16 timestamps=9 |}]

let%expect_test "combinators" =
  let tr = Trace.of_string vcd in
  let net = Net.create () in
  let clk = Option.get (Trace.track_path tr "top.clk") in
  let (Clock.Any c) =
    Clock.define net ~name:"clk" { clock = clk.slot; rule = After_falling; enable = None }
  in
  let data =
    Source.logic c
      (Option.get (Trace.track_path tr "top.data"))
      ~init:0
      (fun l -> match Logic.to_known l with Some b -> Bits.to_int_exn b | None -> -1)
  in
  let en =
    Source.logic c
      (Option.get (Trace.track_path tr "top.en"))
      ~init:false
      (fun l -> Logic.to_string l = "1")
  in
  let prev = Sig.pre ~init:(-1) data in
  let delta = Sig.map2 ( - ) data prev in
  let ch = Sig.changes data in
  let count = Sig.fold ~init:0 (fun n _ -> n + 1) ch in
  let fell = Ev.falling en in
  let gated = Ev.when_ en data in
  let tagged = Ev.tag (Sig.cycle c) ch in
  let both = Ev.union [ Ev.map (fun _ -> "fell") fell; Ev.map (Printf.sprintf "ch%d") ch ] in
  let window =
    Machine.run
      {
        name = "window";
        init = [];
        step =
          (fun ~tick:_ acc d ->
            let acc = d :: acc in
            if List.length acc = 2 then ([], [ List.rev acc ]) else (acc, []));
        finish = (fun acc -> if acc = [] then [] else [ List.rev acc ]);
        every_tick = true;
      }
      data
  in
  let cycle = Sig.cycle c in
  Ev.subscribe
    (Ev.when_ (Sig.const c true) cycle)
    (fun n ->
      Printf.printf "cycle %d: data=%d pre=%d delta=%d count=%d\n" n (Sig.peek data) (Sig.peek prev)
        (Sig.peek delta) (Sig.peek count));
  Ev.subscribe gated (Printf.printf "  gated %d\n");
  Ev.subscribe tagged (fun (d, n) -> Printf.printf "  changed to %d at cycle %d\n" d n);
  Ev.subscribe both (fun l -> Printf.printf "  union [%s]\n" (String.concat ";" l));
  Ev.subscribe (fst window) (fun l ->
      List.iter
        (fun w -> Printf.printf "  window [%s]\n" (String.concat ";" (List.map string_of_int w)))
        l);
  let sched = Result.get_ok (Sched.compile net) in
  let st = Sched.run sched (Sampler.create tr (Net.domains net)) in
  Printf.printf "ticks=%d evals=%d\n" st.ticks.(0) st.node_evals;
  [%expect
    {|
    cycle 0: data=1 pre=-1 delta=2 count=0
      gated 1
    cycle 1: data=3 pre=1 delta=2 count=1
      changed to 3 at cycle 1
      union [fell;ch3]
      window [1;3]
    cycle 2: data=7 pre=3 delta=4 count=2
      changed to 7 at cycle 2
      union [ch7]
    cycle 3: data=7 pre=7 delta=0 count=2
      window [7;7]
    ticks=4 evals=48 |}]

let%expect_test "diagnostics carry the cycle" =
  let tr = Trace.of_string vcd in
  let net = Net.create () in
  let clk = Option.get (Trace.track_path tr "top.clk") in
  let (Clock.Any c) =
    Clock.define net ~name:"clk" { clock = clk.slot; rule = After_falling; enable = None }
  in
  let unused = Option.get (Trace.track_path tr "top.unused") in
  let u = Source.logic c unused ~init:false (fun l -> Logic.to_string l = "1") in
  Diag.emit net (Ev.rising u) (fun () ->
      Some (Diag.make ~source:"test" ~code:"unused.rose" ~paths:[ unused.path ] "unused went high"));
  let sched = Result.get_ok (Sched.compile net) in
  ignore (Sched.run sched (Sampler.create tr (Net.domains net)));
  Seq.iter (Format.printf "%a@." Diag.pp) (Diag.stream net);
  [%expect {|
    warning[unused.rose] test cycle 1 time 4: unused went high
    top.unused |}]
