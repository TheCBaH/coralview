open Coralview

let no_write = 127
let store = 126
let d pc word : Core.dispatched = { d_lane = 0; d_pc = pc; d_word = word }
let w reg value : Core.write = { reg; value }
let r ?(lane = 0) pc idx : Core.retired = { r_lane = lane; r_pc = pc; r_idx = idx; r_trap = false }

(* Steps the cycles from 0 and prints each retirement and the summary, and checks that the charges
   of the retired and in-flight instructions, the discarded ones, and the cycles before the first
   dispatch and with nothing in flight add up to the cycles. *)
let run cycles =
  let retired = ref 0 in
  let st =
    List.fold_left
      (fun (st, cycle) inputs ->
        let st, out = Commits.step ~no_write ~store st cycle inputs in
        List.iter
          (function
            | Commits.Event.Commit c ->
                retired := !retired + c.charged;
                let opt = function Some v -> string_of_int v | None -> "-" in
                Printf.printf "%d: lane %d pc %x word %s disp %s written %s dest %s charged %d\n"
                  c.retired c.lane c.pc (opt c.word) (opt c.dispatched) (opt c.written)
                  (match c.dest with
                  | Some (reg, v) -> Printf.sprintf "%d=%s" reg (opt v)
                  | None -> if c.store then "store" else "-")
                  c.charged
            | In_flight _ -> ())
          out;
        (st, cycle + 1))
      (Commits.start, 0) cycles
    |> fst
  in
  let s = Commits.finish st in
  let in_flight =
    List.fold_left (fun n (f : Commits.flight) -> n + f.charged) 0 (Commits.flights st)
  in
  let discarded = s.discarded in
  Printf.printf "cycles %d before %d empty %d unmatched %d skipped %d missing %d in flight %d%s\n"
    s.cycles s.before s.empty s.unmatched_retires s.skipped s.missing_values s.in_flight
    (String.concat "" (List.map (fun (pc, _, c) -> Printf.sprintf " [%x@%d]" pc c) s.pending));
  Printf.printf "charged: %d retired + %d in flight + %d discarded\n" !retired in_flight discarded;
  assert (!retired + in_flight + discarded + s.before + s.empty = s.cycles)

let%expect_test "an idle trace is all before the first dispatch" =
  run [ ([], [], []); ([], [], []) ];
  [%expect
    {|
    cycles 2 before 2 empty 0 unmatched 0 skipped 0 missing 0 in flight 0
    charged: 0 retired + 0 in flight + 0 discarded |}]

let%expect_test "a dispatch charges its own cycle, and retires in the cycle after" =
  run [ ([ d 0x10 1 ], [], []); ([], [], [ r 0x10 no_write ]); ([], [], []) ];
  [%expect
    {|
    1: lane 0 pc 10 word 1 disp 0 written - dest - charged 2
    cycles 3 before 0 empty 1 unmatched 0 skipped 0 missing 0 in flight 0
    charged: 2 retired + 0 in flight + 0 discarded |}]

let%expect_test "the next dispatch of a retirement's cycle queues behind it, uncharged" =
  run [ ([ d 0x10 1 ], [], []); ([ d 0x14 2 ], [], [ r 0x10 no_write ]) ];
  [%expect
    {|
    1: lane 0 pc 10 word 1 disp 0 written - dest - charged 2
    cycles 2 before 0 empty 0 unmatched 0 skipped 0 missing 0 in flight 1 [14@1]
    charged: 2 retired + 0 in flight + 0 discarded |}]

let%expect_test "a retirement takes the oldest dispatch of its PC and drops the older ones" =
  run [ ([ d 0x10 1; d 0x14 2 ], [], []); ([ d 0x18 3 ], [], []); ([], [], [ r 0x18 no_write ]) ];
  [%expect
    {|
    2: lane 0 pc 18 word 3 disp 1 written - dest - charged 0
    cycles 3 before 0 empty 0 unmatched 0 skipped 2 missing 0 in flight 0
    charged: 0 retired + 0 in flight + 3 discarded |}]

let%expect_test "lanes of one cycle retire in order, and a PC pairs with its dispatches in order" =
  run [ ([ d 0x10 1; d 0x10 1 ], [], []); ([], [], [ r 0x10 no_write; r ~lane:1 0x10 no_write ]) ];
  [%expect
    {|
    1: lane 0 pc 10 word 1 disp 0 written - dest - charged 2
    1: lane 1 pc 10 word 1 disp 0 written - dest - charged 0
    cycles 2 before 0 empty 0 unmatched 0 skipped 0 missing 0 in flight 0
    charged: 2 retired + 0 in flight + 0 discarded |}]

let%expect_test "a retirement with no dispatch for its PC is counted and keeps the queue" =
  run [ ([ d 0x10 1 ], [], []); ([], [], [ r 0x30 no_write ]); ([], [], [ r 0x10 no_write ]) ];
  [%expect
    {|
    1: lane 0 pc 30 word - disp - written - dest - charged 0
    2: lane 0 pc 10 word 1 disp 0 written - dest - charged 3
    cycles 3 before 0 empty 0 unmatched 1 skipped 0 missing 0 in flight 0
    charged: 3 retired + 0 in flight + 0 discarded |}]

let%expect_test "a write of the retirement's own cycle supplies its value" =
  run
    [
      ([ d 0x10 1 ], [], []);
      ([], [ w 10 42 ], [ r 0x10 10 ]);
      ([ d 0x14 2 ], [], []);
      ([], [], [ r 0x14 store ]);
    ];
  [%expect
    {|
    1: lane 0 pc 10 word 1 disp 0 written 1 dest 10=42 charged 2
    3: lane 0 pc 14 word 2 disp 2 written - dest store charged 2
    cycles 4 before 0 empty 0 unmatched 0 skipped 0 missing 0 in flight 0
    charged: 4 retired + 0 in flight + 0 discarded |}]

let%expect_test "a destination with no write to consume is counted" =
  run [ ([ d 0x10 1 ], [], []); ([], [], [ r 0x10 10 ]) ];
  [%expect
    {|
    1: lane 0 pc 10 word 1 disp 0 written - dest 10=- charged 2
    cycles 2 before 0 empty 0 unmatched 0 skipped 0 missing 1 in flight 0
    charged: 2 retired + 0 in flight + 0 discarded |}]

let%expect_test "a surplus write puts every later value of its register one retirement late" =
  run
    [
      ([ d 0x10 1; d 0x14 2 ], [ w 10 1 ], []);
      ([], [ w 10 2 ], [ r 0x10 10 ]);
      ([], [ w 10 3 ], [ r 0x14 10 ]);
    ];
  [%expect
    {|
    1: lane 0 pc 10 word 1 disp 0 written 0 dest 10=1 charged 2
    2: lane 0 pc 14 word 2 disp 0 written 1 dest 10=2 charged 1
    cycles 3 before 0 empty 0 unmatched 0 skipped 0 missing 0 in flight 0
    charged: 3 retired + 0 in flight + 0 discarded |}]

let%expect_test "squashed dispatches passed over by the real ones lose their charges" =
  run
    [
      ([ d 0x10 1 ], [], []);
      ([ d 0x14 2 ], [], []);
      ([], [], []);
      ([ d 0x18 3 ], [], []);
      ([ d 0x10 1 ], [], [ r 0x18 no_write ]);
      ([], [], [ r 0x10 no_write ]);
    ];
  [%expect
    {|
    4: lane 0 pc 18 word 3 disp 3 written - dest - charged 0
    5: lane 0 pc 10 word 1 disp 4 written - dest - charged 1
    cycles 6 before 0 empty 0 unmatched 0 skipped 2 missing 0 in flight 0
    charged: 1 retired + 0 in flight + 5 discarded |}]
