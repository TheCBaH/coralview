open Coralview

let commit pc word ~dispatched ~retired ~charged : Commits.commit =
  {
    lane = 0;
    pc;
    word = Some word;
    dispatched = Some dispatched;
    written = None;
    retired;
    dest = None;
    store = false;
    trap = false;
    charged;
  }

let access pc cycle address region : Memory.Event.access =
  {
    cycle;
    pc;
    access = { Access.address; bytes = 4; write = false; region };
    lanes = [ 0; 1; 2; 3 ];
    data = Hwfrp.Bits.zero 128;
  }

let classify = function 1 -> "mem" | 2 -> "alu" | _ -> "unknown"

let print rows =
  List.iter
    (fun (r : Cost.row) ->
      Printf.printf "%s %s count %d cycles %d d->r %d\n" r.cls r.region r.count r.cycles r.d_to_r)
    rows

let%expect_test "requests join the youngest instance dispatched before them" =
  (* PC 0x10 runs twice: the second instance is dispatched at 10, so a request at 12 is its own,
     whatever the first instance did; a store can request after it retired. *)
  let commits =
    [
      commit 0x10 1 ~dispatched:0 ~retired:6 ~charged:5;
      commit 0x14 2 ~dispatched:6 ~retired:7 ~charged:1;
      commit 0x10 1 ~dispatched:10 ~retired:16 ~charged:6;
    ]
  in
  let accesses = [ access 0x10 3 0x1000 (Some "dtcm"); access 0x10 12 0x20000000 None ] in
  print (Cost.join ~classify ~window:Text.everything commits accesses);
  [%expect
    {|
    mem mem count 1 cycles 6 d->r 6
    mem dtcm count 1 cycles 5 d->r 6
    alu - count 1 cycles 1 d->r 1 |}]

let%expect_test "a window keeps the commits retired in it" =
  let commits =
    [
      commit 0x10 1 ~dispatched:0 ~retired:6 ~charged:5;
      commit 0x14 2 ~dispatched:6 ~retired:7 ~charged:1;
    ]
  in
  let window = { Text.first = 7; last = max_int; pcs = [] } in
  print (Cost.join ~classify ~window commits [ access 0x10 3 0x1000 (Some "dtcm") ]);
  [%expect {| alu - count 1 cycles 1 d->r 1 |}]

let%expect_test "of equal dispatch cycles the later instance takes the request" =
  let commits =
    [
      commit 0x10 1 ~dispatched:5 ~retired:8 ~charged:3;
      commit 0x10 1 ~dispatched:5 ~retired:9 ~charged:4;
    ]
  in
  print (Cost.join ~classify ~window:Text.everything commits [ access 0x10 6 0x1000 (Some "dtcm") ]);
  [%expect {|
    mem dtcm count 1 cycles 4 d->r 4
    mem - count 1 cycles 3 d->r 3 |}]

let%expect_test "a retire without a dispatch is joined by its retire cycle" =
  let unmatched ~retired ~charged =
    { (commit 0x10 1 ~dispatched:0 ~retired ~charged) with word = None; dispatched = None }
  in
  let commits = [ unmatched ~retired:6 ~charged:2; unmatched ~retired:12 ~charged:3 ] in
  (* Before the first retire nothing owns the request; at 6 the first does, and keeps the first it gets. *)
  let accesses =
    [
      access 0x10 5 0x1000 (Some "early");
      access 0x10 6 0x1000 (Some "dtcm");
      access 0x10 11 0x1000 (Some "later");
    ]
  in
  print (Cost.join ~classify ~window:Text.everything commits accesses);
  [%expect {|
    unknown - count 1 cycles 3 d->r 0
    unknown dtcm count 1 cycles 2 d->r 0 |}]

let%expect_test "an instance keeps the region of its first request in the list" =
  let commits = [ commit 0x10 1 ~dispatched:0 ~retired:9 ~charged:7 ] in
  let accesses = [ access 0x10 4 0x1000 (Some "dtcm"); access 0x10 3 0x2000 (Some "ext") ] in
  print (Cost.join ~classify ~window:Text.everything commits accesses);
  [%expect {| mem dtcm count 1 cycles 7 d->r 9 |}]

let%expect_test "a request before every dispatch of its PC, or of another PC, joins nothing" =
  let commits = [ commit 0x10 1 ~dispatched:4 ~retired:9 ~charged:7 ] in
  let accesses = [ access 0x10 3 0x1000 (Some "dtcm"); access 0x14 5 0x1000 (Some "dtcm") ] in
  print (Cost.join ~classify ~window:Text.everything commits accesses);
  [%expect {| mem - count 1 cycles 7 d->r 5 |}]

let%expect_test "a hot PC is joined in time that grows with its instances, not their square" =
  let n = 200_000 in
  let commits =
    List.init n (fun k -> commit 0x10 1 ~dispatched:(2 * k) ~retired:((2 * k) + 1) ~charged:1)
  in
  (* Instance k, dispatched at 2k, requests at 2k + 1; every even instance makes one. *)
  let accesses =
    List.filter_map
      (fun k -> if k mod 2 = 0 then Some (access 0x10 ((2 * k) + 1) 0x1000 (Some "dtcm")) else None)
      (List.init n Fun.id)
  in
  print (Cost.join ~classify ~window:Text.everything commits accesses);
  [%expect
    {|
    mem - count 100000 cycles 100000 d->r 100000
    mem dtcm count 100000 cycles 100000 d->r 100000 |}]
