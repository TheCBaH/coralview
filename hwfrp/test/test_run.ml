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
  let tr = Trace.of_string vcd in
  let net = Net.create () in
  let clk = Option.get (Trace.track_path tr "top.clk") in
  match Clock.define net ~name:"clk" { clock = clk.slot; rule = Before_rising; enable = None } with
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
      while Run.step r do
        incr steps;
        if !steps <> !n then print_endline "subscriber behind"
      done;
      let st = Run.finish r in
      let st' = Run.finish r in
      Printf.printf "steps %d ticks %d same %b step-after %b\n" !steps st.ticks.(0) (st == st')
        (Run.step r);
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
