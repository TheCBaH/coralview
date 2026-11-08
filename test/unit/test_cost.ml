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
