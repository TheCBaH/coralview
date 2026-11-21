open Hwfrp

(* Six rising edges of clk; d counts them. *)
let vcd =
  let b = Buffer.create 256 in
  Buffer.add_string b
    {|$timescale 1ps $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 4 " d $end
$upscope $end
$enddefinitions $end
#0
$dumpvars
0!
b0 "
$end
|};
  for i = 1 to 6 do
    Printf.bprintf b "#%d\n1!\n#%d\n0!\nb%s \"\n"
      ((2 * i) - 1)
      (2 * i)
      (String.init 4 (fun j -> if i land (1 lsl (3 - j)) <> 0 then '1' else '0'))
  done;
  Buffer.contents b

type 'c env = { tr : Trace.t; net : Net.t; clk : 'c Clock.t; d : (int, 'c) Sig.t }
type any_env = E : 'c env -> any_env

let env () =
  let tr = Hwfrp_vcd.of_string vcd in
  let net = Net.create () in
  let clk = Option.get (Trace.track_path tr "top.clk") in
  match
    Clock.define net ~name:"clk"
      { clock = clk.slot; rule = Before_rising; enable = None; reset = None }
  with
  | Clock.Any c ->
      let d =
        Source.value c
          (Option.get (Trace.track_path tr "top.d"))
          ~init:0
          (function Vcd_types.Value.Int n -> n | _ -> -1)
      in
      E { tr; net; clk = c; d }

let sampler e = Sampler.create e.tr (Net.domains e.net)
let every e = Ev.when_ (Sig.const e.clk true) (Sig.cycle e.clk)

(* A machine over d that emits d at odd values and, at the end, 100. *)
let machine e =
  fst
    (Machine.run
       {
         name = "m";
         init = ();
         step = (fun ~tick:_ () d -> ((), if d land 1 = 1 then [ d ] else []));
         finish = (fun () -> [ 100 ]);
         every_tick = false;
       }
       e.d)

let%expect_test "Run steps a sample at a time" =
  match env () with
  | E e ->
      let n = ref 0 in
      Ev.subscribe (every e) (fun _ -> incr n);
      let r = Run.start (Result.get_ok (Sched.compile e.net)) (sampler e) in
      let steps = ref 0 in
      while Run.step r = Run.Stepped do
        incr steps;
        if !steps <> !n then print_endline "subscriber behind"
      done;
      let st = Run.finish r in
      let st' = Run.finish r in
      Printf.printf "steps %d ticks %d same %b step-after %b\n" !steps st.ticks.(0) (st == st')
        (Run.step r <> Run.Ended);
      [%expect {| steps 6 ticks 6 same true step-after false |}]

let%expect_test "Port pulls what a subscriber sees, finisher events last" =
  match env () with
  | E e ->
      let out = Ev.flatten (machine e) in
      let seen = ref [] in
      Ev.subscribe out (fun l -> seen := l :: !seen);
      let p = Port.create out and c = Port.create (every e) in
      let r = Run.start (Result.get_ok (Sched.compile e.net)) (sampler e) in
      let s = Port.seq r p in
      (match s () with
      | Seq.Cons (x, rest) ->
          Printf.printf "first [%s]; cycles queued %d\n"
            (String.concat ";" (List.map string_of_int x))
            (Port.pending c);
          Seq.iter
            (fun l -> Printf.printf "then [%s]\n" (String.concat ";" (List.map string_of_int l)))
            rest
      | Nil -> print_endline "empty");
      Printf.printf "subscriber saw %d; cycles queued %d\n" (List.length !seen) (Port.pending c);
      (try ignore (s ()) with Invalid_argument m -> print_endline m);
      (try
         let (_ : _ Seq.t) = Port.seq r p in
         ()
       with Invalid_argument m -> print_endline m);
      Printf.printf "cycles pulled %d\n" (Seq.length (Port.seq r c));
      [%expect
        {|
    first [1]; cycles queued 2
    then [3]
    then [5]
    then [100]
    subscriber saw 4; cycles queued 6
    Port.seq: the sequence is ephemeral and was already traversed
    Port.seq: the port is already read
    cycles pulled 6
    |}]

let pp_out = function
  | Track.Closed v -> "closed " ^ v
  | Open_at_end v -> "open-at-end " ^ v
  | Displaced v -> "displaced " ^ v

let%expect_test "Track" =
  match env () with
  | E e ->
      let script = function
        | 0 -> [ Track.Open (1, "a"); Open (2, "b") ]
        | 1 -> [ Update (1, fun v -> v ^ "+"); Close 1 ]
        | 2 -> [ Open (1, "c") ]
        | 3 -> [ Open (2, "d"); Update (5, Fun.id) ]
        | 4 -> [ Close 9; Close 2 ]
        | 5 -> [ Open (3, "e"); Close 3 ]
        | _ -> []
      in
      let at_end =
        Ev.filter_map
          (fun l -> if List.mem 100 l then Some [ Track.Open (100, "m100") ] else None)
          (machine e)
      in
      let ops = Ev.merge ( @ ) (Ev.filter (( <> ) []) (Ev.map script (every e))) at_end in
      let t = Track.run ~name:"t" ops in
      Ev.subscribe
        (Ev.tag (Sig.cycle e.clk) t)
        (fun (l, c) -> Printf.printf "cycle %d: %s\n" c (String.concat ", " (List.map pp_out l)));
      ignore (Sched.run (Result.get_ok (Sched.compile e.net)) (sampler e));
      Seq.iter (fun d -> Format.printf "%a@." Diag.pp d) (Diag.stream e.net);
      [%expect
        {|
    cycle 1: closed a+
    cycle 3: displaced b
    cycle 4: closed d
    cycle 5: closed e
    cycle 5: open-at-end c, open-at-end m100
    warning[track.reopened] t cycle 3 time 7: opened a key that is still open
    warning[track.not-open] t cycle 3 time 7: updated a key that is not open
    warning[track.not-open] t cycle 4 time 9: closed a key that is not open
    |}]

(* The statistics read time from the injected clock only. *)
let%expect_test "stats clock" =
  let run ?clock () =
    let (E e) = env () in
    let sched = Result.get_ok (Sched.compile e.net) in
    (Sched.run ?clock sched (sampler e)).wall_s
  in
  let t = ref 10. in
  let clock () =
    t := !t +. 1.5;
    !t
  in
  Printf.printf "none=%g injected=%g\n" (run ()) (run ~clock ());
  [%expect {| none=0 injected=1.5 |}]

(* A machine fed by another machine's output: it counts the items it is given. [flush] makes the
   upstream machine emit one more at the end; [composed] gives the downstream ones a [finish_input]. *)
let chain strategy ~flush ~composed =
  let (E e) = env () in
  let a =
    fst
      (Machine.run
         {
           name = "a";
           init = ();
           step = (fun ~tick:_ () d -> ((), if d land 1 = 1 then [ d ] else []));
           finish = (fun () -> if flush then [ 100 ] else []);
           every_tick = false;
         }
         e.d)
  in
  let calls = ref 0 in
  let counter name ?finish_input input =
    let items = function Some l -> List.length l | None -> 0 in
    fst
      (Machine.run ?finish_input
         {
           name;
           init = 0;
           step = (fun ~tick:_ n i -> (n + items i, []));
           finish = (fun n -> [ n ]);
           every_tick = true;
         }
         (Ev.current input))
  in
  let fin =
    if composed then
      Some
        (fun n i ->
          incr calls;
          ((n + match i with Some l -> List.length l | None -> 0), []))
    else None
  in
  let b = counter "b" ?finish_input:fin a in
  let c =
    counter "c"
      ?finish_input:
        (if composed then
           Some (fun n i -> ((n + match i with Some l -> List.hd l * 10 | None -> 0), []))
         else None)
      b
  in
  Ev.subscribe b (fun l ->
      Printf.printf "b ends with %s\n" (String.concat "," (List.map string_of_int l)));
  Ev.subscribe c (fun l ->
      Printf.printf "c ends with %s\n" (String.concat "," (List.map string_of_int l)));
  let st = Sched.run (Result.get_ok (Sched.compile ~strategy e.net)) (sampler e) in
  Printf.printf "ticks %d, finish_input of b called %d times\n" st.ticks.(0) !calls

let%expect_test "machines compose at the end of the trace through finish_input" =
  List.iter
    (fun (strategy, name) ->
      Printf.printf "%s, flush, plain\n" name;
      chain strategy ~flush:true ~composed:false;
      Printf.printf "%s, flush, composed\n" name;
      chain strategy ~flush:true ~composed:true;
      Printf.printf "%s, no flush, composed\n" name;
      chain strategy ~flush:false ~composed:true)
    [ (Sched.Incremental, "incremental"); (Sweep, "sweep") ];
  [%expect
    {|
    incremental, flush, plain
    b ends with 3
    c ends with 0
    ticks 6, finish_input of b called 0 times
    incremental, flush, composed
    b ends with 4
    c ends with 40
    ticks 6, finish_input of b called 1 times
    incremental, no flush, composed
    b ends with 3
    c ends with 30
    ticks 6, finish_input of b called 0 times
    sweep, flush, plain
    b ends with 3
    c ends with 0
    ticks 6, finish_input of b called 0 times
    sweep, flush, composed
    b ends with 4
    c ends with 40
    ticks 6, finish_input of b called 1 times
    sweep, no flush, composed
    b ends with 3
    c ends with 30
    ticks 6, finish_input of b called 0 times |}]

(* The end of the input: the rising edges at #1 and #3 are sampled after applying their changes. *)
let ending tail =
  Printf.sprintf
    {|$timescale 1ps $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 4 " d $end
$upscope $end
$enddefinitions $end
#0
$dumpvars
0!
b0 "
$end
#1
1!
b1 "
#2
0!
#3
1!
b10 "%s|}
    tail

(* Counts the samples and keeps d; its finisher reports both. *)
let ends text =
  let tr = Hwfrp_vcd.of_string text in
  let net = Net.create () in
  let clk = Option.get (Trace.track_path tr "top.clk") in
  let (Clock.Any c) =
    Clock.define net ~name:"clk"
      { clock = clk.slot; rule = After_rising; enable = None; reset = None }
  in
  let d =
    Source.value c
      (Option.get (Trace.track_path tr "top.d"))
      ~init:0
      (function Vcd_types.Value.Int n -> n | _ -> -1)
  in
  let m =
    fst
      (Machine.run
         {
           name = "m";
           init = (0, -1);
           step = (fun ~tick:_ (n, _) d -> ((n + 1, d), []));
           finish = (fun (n, d) -> [ (n, d) ]);
           every_tick = true;
         }
         d)
  in
  Ev.subscribe m (List.iter (fun (n, d) -> Printf.printf "finish after %d samples, d=%d\n" n d));
  let sched = Result.get_ok (Sched.compile net) in
  let r = Run.start sched (Sampler.create tr (Net.domains net)) in
  let st = Run.finish r in
  Printf.printf "ticks %d\n" st.ticks.(0);
  Seq.iter (fun d -> Format.printf "%a@." Diag.pp d) (Diag.stream net)

let%expect_test "the end of the input" =
  print_endline "cut inside the last timestamp";
  ends (ending "");
  print_endline "ends after the edge's timestamp";
  ends (ending "\n");
  print_endline "changes after the last edge are applied but not sampled";
  ends (ending "\n#4\n0!\nb11 \"\n#5\nb100 \"");
  print_endline "a last timestamp with no changes";
  ends (ending "\n#9\n");
  print_endline "no edge at all";
  ends
    {|$scope module top $end
$var wire 1 ! clk $end
$var wire 4 " d $end
$upscope $end
$enddefinitions $end
#0
b0 "
#5
b11 "
|};
  [%expect
    {|
    cut inside the last timestamp
    finish after 2 samples, d=2
    ticks 2
    ends after the edge's timestamp
    finish after 2 samples, d=2
    ticks 2
    changes after the last edge are applied but not sampled
    finish after 2 samples, d=2
    ticks 2
    a last timestamp with no changes
    finish after 2 samples, d=2
    ticks 2
    no edge at all
    finish after 0 samples, d=-1
    ticks 0
    warning[clock.no-edges] clk cycle 0 time 0: the clock domain never ticked |}]

(* A finisher's events stay in its clock domain: the other one reads the resampled signal as it was. *)
let%expect_test "finish does not cross clock domains" =
  let tr = Hwfrp_vcd.of_string (ending "") in
  let net = Net.create () in
  let clk = Option.get (Trace.track_path tr "top.clk") in
  let define name rule =
    Clock.define net ~name { clock = clk.slot; rule; enable = None; reset = None }
  in
  let (Clock.Any c0) = define "rising" After_rising in
  let (Clock.Any c1) = define "falling" After_falling in
  let flushed = Sig.hold ~init:0 (Ev.at_finish c0 (fun () -> 7)) in
  let across = Clock_cross.resample flushed c1 in
  Ev.subscribe (Ev.at_finish c0 (fun () -> 8)) (Printf.printf "domain 0 finishes with %d\n");
  let calls = ref 0 in
  let m =
    fst
      (Machine.run
         ~finish_input:(fun s i ->
           incr calls;
           (s + i, []))
         (Machine.of_fold ~finish:(fun s -> [ s ]) ~name:"m" ~init:0 (fun s _ -> (s, [])))
         across)
  in
  Ev.subscribe m (List.iter (Printf.printf "domain 1 finishes with %d\n"));
  ignore (Sched.run (Result.get_ok (Sched.compile net)) (Sampler.create tr (Net.domains net)));
  Printf.printf "hold %d, resampled %d, finish_input calls %d\n" (Sig.peek flushed)
    (Sig.peek across) !calls;
  [%expect
    {|
    domain 0 finishes with 8
    domain 1 finishes with 0
    hold 7, resampled 0, finish_input calls 0 |}]

let%expect_test "a finisher that raises runs once" =
  let (E e) = env () in
  Ev.subscribe
    (Ev.at_finish e.clk (fun () -> "flush"))
    (fun s ->
      print_endline s;
      failwith "sink closed");
  let r = Run.start (Result.get_ok (Sched.compile e.net)) (sampler e) in
  let attempt () = match Run.finish r with _ -> () | exception Failure m -> print_endline m in
  attempt ();
  attempt ();
  [%expect {|
    flush
    sink closed
    sink closed |}]

(* rst is unknown until #2, high until #6, low after; d is unknown until #4. *)
let reset_vcd =
  {|$timescale 1ps $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 1 " rst $end
$var wire 4 # d $end
$upscope $end
$enddefinitions $end
#0
$dumpvars
0!
x"
bx #
$end
#1
1!
#2
0!
1"
#3
1!
#4
0!
b1 #
#5
1!
#6
0!
0"
#7
1!
b10 #
#8
0!
#9
1!
#10
0!
bx #
|}

let%expect_test "a reset marks its samples and silences unknown bits in them" =
  let tr = Hwfrp_vcd.of_string reset_vcd in
  let net = Net.create () in
  let at n = Vcd_types.Reference.of_list [ "top"; n ] in
  let (Clock.Any c) =
    Bind.clock net tr ~model:"m" ~name:"clk" ~reset:(at "rst", true) After_falling (at "clk")
  in
  let d =
    Bind.signal
      (Bind.root net tr c ~model:"m" (Vcd_types.Reference.of_list [ "top" ]))
      "d" Bind.uint
  in
  let rst = Sig.in_reset c and cycle = Sig.cycle c in
  Ev.subscribe
    (Ev.when_ (Sig.const c true) (Sig.map2 (fun r d -> (r, d)) rst d))
    (fun (r, d) -> Printf.printf "cycle %d in_reset %b d %d\n" (Sig.peek cycle) r d);
  let st = Sched.run (Result.get_ok (Sched.compile net)) (Sampler.create tr (Net.domains net)) in
  Printf.printf "ticks %d in_reset %d\n" st.ticks.(0) st.in_reset.(0);
  Seq.iter (Format.printf "%a@." Diag.pp) (Diag.stream net);
  [%expect
    {|
    cycle 0 in_reset true d 0
    cycle 1 in_reset true d 1
    cycle 2 in_reset false d 1
    cycle 3 in_reset false d 2
    cycle 4 in_reset false d 0
    ticks 5 in_reset 2
    warning[bind.unknown-bits] m cycle 4 time 10: uint of xxxx
    top.d |}]

let%expect_test "a run that never leaves reset says so" =
  let tr = Hwfrp_vcd.of_string reset_vcd in
  let net = Net.create () in
  let at n = Vcd_types.Reference.of_list [ "top"; n ] in
  let (Clock.Any _) =
    Bind.clock net tr ~model:"m" ~name:"clk" ~reset:(at "clk", false) After_falling (at "clk")
  in
  ignore (Sched.run (Result.get_ok (Sched.compile net)) (Sampler.create tr (Net.domains net)));
  Seq.iter (Format.printf "%a@." Diag.pp) (Diag.stream net);
  [%expect
    {| warning[clock.always-in-reset] clk cycle 4 time 10: the reset was asserted at all 5 clock samples |}]
