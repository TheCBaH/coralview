(* A run fed in pieces, and paused, gives the events of the whole input at once. *)
open Hwfrp
open Vcd_types

(* [cycles] falling edges of clk; d counts them, changing with the edge. *)
let text cycles =
  let b = Buffer.create 256 in
  Buffer.add_string b
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
|};
  for i = 1 to cycles do
    Printf.bprintf b "#%d\n1!\n#%d\n0!\nb%s \"\n"
      ((2 * i) - 1)
      (2 * i)
      (String.init 8 (fun j -> if i land (1 lsl (7 - j)) <> 0 then '1' else '0'))
  done;
  Buffer.contents b

(* The cycle and d at each sample, then a final event from a finisher. *)
let build tr =
  let net = Net.create () in
  let c = Option.get (Trace.track_path tr "top.clk") in
  let (Clock.Any clk) =
    Clock.define net ~name:"clk" { clock = c.slot; rule = After_falling; enable = None }
  in
  let d =
    Source.value clk
      (Option.get (Trace.track_path tr "top.d"))
      ~init:0
      (function Value.Int n -> n | _ -> -1)
  in
  let every = Ev.tag (Sig.cycle clk) (Ev.when_ (Sig.const clk true) d) in
  let ops = Ev.map (fun (d, c) -> [ Track.Open (c, d) ]) every in
  let closed =
    Ev.map
      (fun l -> List.map (function Track.Open_at_end (d : int) -> (-1, d) | _ -> (0, 0)) l)
      (Track.run ops)
  in
  let outs = Ev.map (fun (d, c) -> [ (c, d) ]) every in
  (Port.create outs, Port.create closed, net)

let reference cycles =
  let tr = Hwfrp_vcd.of_string (text cycles) in
  let p, q, net = build tr in
  let run = Run.start (Result.get_ok (Sched.compile net)) (Sampler.create tr (Net.domains net)) in
  let a = List.of_seq (Port.seq run p) and b = List.concat (List.of_seq (Port.seq run q)) in
  (a, b)

let events cycles =
  let { Vcd.header; simulation } = Vcd.parse_string (text cycles) in
  (header, Array.of_seq simulation)

type step = { pushed : int; starved : int; paused : int }

(* Feed [batch] events at a time, reading everything available between feeds; with [pause], pause the
   run after every item and check that a paused run consumes nothing. *)
let live ?(pause = false) cycles batch =
  let header, evs = events cycles in
  let src = In_memory.Live.create header in
  let tr = In_memory.Live.trace src in
  let p, q, net = build tr in
  let run = Run.start (Result.get_ok (Sched.compile net)) (Sampler.create tr (Net.domains net)) in
  let got = ref [] and tail = ref [] and starved = ref 0 and paused = ref 0 in
  let rec drain () =
    match Port.poll run p with
    | Port.Item x ->
        got := x :: !got;
        if pause then begin
          Run.pause run;
          let queued = In_memory.Live.queued src in
          (match Port.poll run p with Port.Paused -> incr paused | _ -> failwith "not paused");
          assert (In_memory.Live.queued src = queued);
          Run.resume run
        end;
        drain ()
    | Starved -> incr starved
    | Ended ->
        let rec rest () =
          match Port.poll run q with
          | Port.Item x ->
              tail := List.rev_append x !tail;
              rest ()
          | _ -> ()
        in
        rest ()
    | Paused -> failwith "unexpected pause"
  in
  let n = Array.length evs in
  let i = ref 0 in
  while !i < n do
    for _ = 1 to min batch (n - !i) do
      In_memory.Live.push src evs.(!i);
      incr i
    done;
    if !i = n then In_memory.Live.finish src;
    drain ()
  done;
  ((List.rev !got, List.rev !tail), { pushed = n; starved = !starved; paused = !paused })

let%test "any batch size gives the events of the whole input" =
  let want = reference 12 in
  fst want <> []
  && List.for_all (fun batch -> fst (live 12 batch) = want) [ 1; 2; 3; 4; 5; 7; 13; 29; 1000 ]

let%test "a small batch starves, a whole input does not" =
  (snd (live 12 1)).starved > 1 && (snd (live 12 1000)).starved = 0

let%test "pausing between items changes nothing" =
  let want = reference 12 in
  List.for_all
    (fun batch ->
      let got, st = live ~pause:true 12 batch in
      got = want && st.paused = List.length (fst want))
    [ 1; 3; 1000 ]

let%test "finishers fire once, after the end" =
  let a, b = reference 12 in
  List.length a = 12 && b = List.init 12 (fun i -> (-1, i + 1))

let raises f = match f () with exception Invalid_argument _ -> true | _ -> false

let%test "finish, seq and push refuse a run that cannot go on" =
  let header, evs = events 4 in
  let src = In_memory.Live.create header in
  let tr = In_memory.Live.trace src in
  let p, _, net = build tr in
  let run = Run.start (Result.get_ok (Sched.compile net)) (Sampler.create tr (Net.domains net)) in
  In_memory.Live.push src evs.(0);
  Port.poll run p = Port.Starved
  && Run.step run = Run.Starved
  && raises (fun () -> Run.finish run)
  && raises (fun () -> Seq.length (Port.seq run p))
  && begin
    Run.pause run;
    Run.paused run && Run.step run = Run.Paused && raises (fun () -> Run.finish run)
  end
  && begin
    Run.resume run;
    Array.iteri (fun i e -> if i > 0 then In_memory.Live.push src e) evs;
    In_memory.Live.finish src;
    ignore (Run.finish run);
    Run.step run = Run.Ended && raises (fun () -> In_memory.Live.push src evs.(0))
  end
