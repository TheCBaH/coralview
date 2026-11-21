open Hwfrp_sinks

let%expect_test "json keeps the key order and escapes" =
  print_endline
    (Json.to_string
       (Obj
          [
            ("z", Int 1);
            ("a", Str "q\"\\\n\t\r\001\031\127é");
            ("n", Null);
            ("l", List [ Bool true; Bool false; Obj [] ]);
          ]));
  [%expect {| {"z":1,"a":"q\"\\\n\t\r\u0001\u001F\u007Fé","n":null,"l":[true,false,{}]} |}]

let%expect_test "jsonl and lines" =
  let recs = List.to_seq [ Json.Obj [ ("ev", Str "a"); ("t", Int 1) ]; Obj [ ("ev", Str "b") ] ] in
  print_string (Jsonl.to_string ~header:(Obj [ ("format", Str "x/1") ]) recs);
  print_string (Jsonl.to_string recs);
  print_string (Lines.to_string (List.to_seq [ "one"; "two" ]));
  print_string (Lines.to_string Seq.empty);
  [%expect
    {|
    {"format":"x/1"}
    {"ev":"a","t":1}
    {"ev":"b"}
    {"ev":"a","t":1}
    {"ev":"b"}
    one
    two |}]

let chrome_events : Chrome_trace.event list =
  [
    Span { lane = "bus"; name = "read"; start = 3; stop = 5; args = [ ("a", Str "0x10") ] };
    Span { lane = "instr"; name = "nop"; start = 1; stop = 1; args = [] };
    Instant { lane = "ctl"; name = "reset"; at = 0; args = [] };
    Counter { name = "pc"; at = 2; value = 16 };
  ]

let%expect_test "chrome trace: lanes in declared order, then first use" =
  print_string
    (Chrome_trace.to_string ~time_unit:"ms"
       [
         { name = "core"; lanes = [ "instr"; "bus" ]; events = List.to_seq chrome_events };
         { name = "empty"; lanes = []; events = Seq.empty };
       ]);
  [%expect
    {|
    {"displayTimeUnit":"ms","traceEvents":[
    {"ph":"M","pid":1,"name":"process_name","args":{"name":"core"}},
    {"ph":"M","pid":1,"tid":1,"name":"thread_name","args":{"name":"instr"}},
    {"ph":"M","pid":1,"tid":2,"name":"thread_name","args":{"name":"bus"}},
    {"ph":"X","pid":1,"tid":2,"name":"read","ts":3,"dur":3,"args":{"a":"0x10"}},
    {"ph":"X","pid":1,"tid":1,"name":"nop","ts":1,"dur":1,"args":{}},
    {"ph":"M","pid":1,"tid":3,"name":"thread_name","args":{"name":"ctl"}},
    {"ph":"i","s":"t","pid":1,"tid":3,"name":"reset","ts":0,"args":{}},
    {"ph":"C","pid":1,"name":"pc","ts":2,"args":{"value":16}},
    {"ph":"M","pid":2,"name":"process_name","args":{"name":"empty"}}
    ]}
    |}]

let%expect_test "occupancy" =
  let show =
    List.iter (function
      | Chrome_trace.Counter { at; value; _ } -> Printf.printf "%d:%d " at value
      | _ -> ())
  in
  show (Chrome_trace.occupancy ~name:"q" [ (1, Some 3); (2, Some 2); (5, None) ] ~last:7);
  print_newline ();
  show (Chrome_trace.occupancy ~name:"q" [] ~last:0);
  [%expect {|
    1:1 2:2 3:1 4:0 5:1 8:0 |}]

let%expect_test "no process" =
  print_string (Chrome_trace.to_string []);
  [%expect {|
    {"displayTimeUnit":"ns","traceEvents":[
    ]}
    |}]

let%expect_test
    "chrome trace: a lazy sequence gives the same bytes, each event written before the next is \
     pulled" =
  let process events : Chrome_trace.process = { name = "core"; lanes = [ "instr" ]; events } in
  let expect = Chrome_trace.to_string ~time_unit:"ms" [ process (List.to_seq chrome_events) ] in
  let file = Filename.temp_file "chrome" ".json" in
  let oc = open_out_bin file in
  let at = ref [] in
  let lazy_events =
    Seq.map
      (fun e ->
        at := pos_out oc :: !at;
        e)
      (List.to_seq chrome_events)
  in
  Chrome_trace.output oc ~time_unit:"ms" [ process lazy_events ];
  close_out oc;
  let got = In_channel.with_open_bin file In_channel.input_all in
  Sys.remove file;
  Printf.printf "same bytes: %b\n" (got = expect);
  (* Each pull finds the bytes of the events before it already written: the position grows. *)
  let at = List.rev !at in
  Printf.printf "pulled %d, written before each pull strictly growing: %b\n" (List.length at)
    (List.for_all2 ( < ) (List.filteri (fun i _ -> i < 3) at) (List.tl at));
  [%expect {|
    same bytes: true
    pulled 4, written before each pull strictly growing: true |}]
