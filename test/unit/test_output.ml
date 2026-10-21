open Coralview

let commit : Commits.Event.t =
  Commit
    {
      lane = 0;
      pc = 0x10;
      word = Some 0x13;
      dispatched = Some 1;
      written = None;
      retired = 3;
      dest = Some (10, Some 7);
      store = false;
      trap = false;
      charged = 2;
    }

let in_flight : Commits.Event.t = In_flight { pc = 0x14; word = 0x33; cycle = 2; charged = 1 }
let commits = (module Commits : Output.OUTPUT with type Event.t = Commits.Event.t)

let show = function
  | Ok _ -> "ok"
  | Error e -> "error: " ^ List.hd (String.split_on_char (Char.chr 10) e)

let%expect_test "events round-trip without a header" =
  let lines = List.map (Output.encode_event commits) [ commit; in_flight ] in
  List.iter print_endline lines;
  let back = List.of_seq (Output.decode_events commits (List.to_seq lines)) in
  assert (back = [ Ok commit; Ok in_flight ]);
  [%expect
    {|
      {"type":"commits.commit","lane":0,"instance":{"pc":16,"word":19,"dispatched":1,"retired":3},"dest":{"reg":10,"value":7},"store":false,"trap":false,"charged":2}
      {"type":"commits.in_flight","pc":20,"word":51,"dispatched":2,"charged":1}
    |}]

let%expect_test "decoding is lazy and an error does not end the sequence" =
  let pulled = ref 0 in
  let lines =
    Seq.map
      (fun l ->
        incr pulled;
        l)
      (List.to_seq [ "{"; Output.encode_event commits in_flight; "[]" ])
  in
  let decoded = Output.decode_events commits lines in
  Printf.printf "built: %d\n" !pulled;
  List.iter (fun r -> print_endline (show r)) (List.of_seq decoded);
  [%expect
    {|
      built: 0
      error: Unclosed commits.event object
      ok
      error: Expected commits.event object but found array
    |}]

let%expect_test "an invalid record is an error, not an exception" =
  let decode = Output.decode_event commits in
  List.iter
    (fun l -> print_endline (show (decode l)))
    [
      "";
      "not json";
      {|{"type":"commits.nothing"}|};
      {|{"type":"commits.in_flight","pc":"x","word":1,"cycle":1,"charged":1}|};
      {|{"pc":1}|};
    ];
  [%expect
    {|
      error: Expected JSON value but found end of text
      error: Expected commits.event object but found null
      error: Unexpected member type value in commits.event object: <tag>.
      error: String "x" does not parse to OCaml int value
      error: Missing member type in commits.event object
    |}]

let%expect_test "a decoder that raises is an error" =
  print_endline (show (Codec.of_line Codec.stats {|{"n":2,"sum":3}|}));
  print_endline (show (Codec.of_line Codec.bits {|"zz"|}));
  print_endline (show (Codec.of_line Codec.stats {|{"n":0,"sum":0}|}));
  [%expect {|
      error: option is None
      error: int_of_string
      ok
    |}]
