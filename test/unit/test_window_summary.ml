open Coralview

let commit pc ~retired ~charged : Commits.commit =
  {
    lane = 0;
    pc;
    word = None;
    dispatched = None;
    written = None;
    retired;
    dest = None;
    store = false;
    trap = false;
    charged;
  }

let span reason lane start stop : Stalls.Event.stall_span =
  { lane; reason; pc = 0; word = 0; span = { Hwfrp.Span.start; stop } }

let op pc cycle ops : Ops.op =
  {
    cycle;
    pc = Some pc;
    unit = "alu";
    mnemonic = None;
    sew = 32;
    lmul = "1";
    lmul_orig = None;
    vl = 4;
    vstart = 0;
    tile = None;
    kind = Ops.Arith;
    float = false;
    elements = 4;
    ops;
  }

let commits =
  [
    commit 0x10 ~retired:5 ~charged:4;
    commit 0x14 ~retired:9 ~charged:3;
    commit 0x18 ~retired:20 ~charged:10;
  ]

let stalls =
  [
    span Stalls.Raw 0 2 (Some 6);
    span Stalls.Empty 1 8 (Some 12) (* 5 cycles, 3 inside [8, 10] *);
    span Stalls.Raw 0 18 None (* open: to the end, cycle 24 *);
  ]
  |> List.map (fun (s : Stalls.Event.stall_span) -> s)

let print window =
  let s =
    Window_summary.make ~window ~end_cycle:24 ~commits ~accesses:None
      ~ops:(Some [ op 0x14 8 6; op 0x18 19 2 ])
      ~stalls:(Some stalls)
  in
  Window_summary.text s;
  print_endline (Codec.to_line Window_summary.jsont s)

let%expect_test "a window counts its commits, ops, and the cycles of the spans inside it" =
  print Text.everything;
  [%expect
    {|
    window [0, end]
      instructions 3, cycles charged 17
      vector: 2 instructions, 8 operations
      dispatch lane-cycles: empty 5, raw 12
    {"type":"summary.window","first":0,"instructions":3,"cycles":17,"vector_instructions":2,"vector_ops":8,"stalls":[{"reason":"empty","lane_cycles":5},{"reason":"raw","lane_cycles":12}]} |}];
  print { Text.everything with first = 8; last = 10 };
  [%expect
    {|
    window [8, 10]
      instructions 1, cycles charged 3
      vector: 1 instructions, 6 operations
      dispatch lane-cycles: empty 3
    {"type":"summary.window","first":8,"last":10,"instructions":1,"cycles":3,"vector_instructions":1,"vector_ops":6,"stalls":[{"reason":"empty","lane_cycles":3}]} |}]

let%expect_test "the hottest loop of the window, with its median cycles a trip" =
  let commits =
    [
      commit 0x10 ~retired:5 ~charged:4;
      commit 0x14 ~retired:9 ~charged:3;
      commit 0x10 ~retired:12 ~charged:2;
      commit 0x14 ~retired:14 ~charged:1;
      commit 0x18 ~retired:20 ~charged:10;
    ]
  in
  let s =
    Window_summary.make ~window:Text.everything ~end_cycle:24 ~commits ~accesses:None ~ops:None
      ~stalls:None
  in
  Window_summary.text s;
  print_endline (Codec.to_line Window_summary.jsont s);
  [%expect
    {|
    window [0, end]
      instructions 5, cycles charged 20
      hottest loop 00000010: 2 trips, 3 cycles a trip
    {"type":"summary.window","first":0,"instructions":5,"cycles":20,"hot_loop":{"header":16,"trips":2,"cycles_per_trip":3}} |}]
