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

let%expect_test "json floats print the shortest text that reads back, and never as an int" =
  let show f = print_endline (Json.to_string (Float f)) in
  List.iter show
    [
      0.;
      -0.;
      1.;
      -2.5;
      0.5;
      0.1;
      1. /. 3.;
      3.14159;
      123456789.125;
      1e15;
      1e21;
      1.5e-7;
      max_float;
      min_float;
      5e-324;
      -1.7976931348623157e308;
    ];
  [%expect
    {|
      0.0
      -0.0
      1.0
      -2.5
      0.5
      0.1
      0.3333333333333333
      3.14159
      123456789.125
      1e+15
      1e+21
      1.5e-07
      1.7976931348623157e+308
      2.2250738585072014e-308
      4.94065645841247e-324
      -1.7976931348623157e+308 |}];
  List.iter show [ nan; infinity; neg_infinity ];
  [%expect {|
    null
    null
    null |}];
  print_endline (Json.to_string (List [ Float 1.; Int 1; Obj [ ("t", Float 0.25) ] ]));
  [%expect {| [1.0,1,{"t":0.25}] |}]

let json_number_ok s =
  let n = String.length s in
  let i = ref 0 in
  let digits () =
    let j = !i in
    while !i < n && s.[!i] >= '0' && s.[!i] <= '9' do
      incr i
    done;
    !i > j
  in
  if !i < n && s.[!i] = '-' then incr i;
  digits ()
  && (if !i < n && s.[!i] = '.' then (
        incr i;
        digits ())
      else true)
  && ((not (!i < n && (s.[!i] = 'e' || s.[!i] = 'E')))
     || begin
       incr i;
       if !i < n && (s.[!i] = '+' || s.[!i] = '-') then incr i;
       digits ()
     end)
  && !i = n

let float_round_trip =
  QCheck2.Test.make ~name:"json float round trip" ~count:20000
    QCheck2.Gen.(
      oneof [ float; map Int64.float_of_bits int64; map (fun n -> float_of_int n /. 1000.) int ])
    (fun f ->
      let s = Json.to_string (Float f) in
      if Float.is_finite f then
        json_number_ok s
        && Int64.equal (Int64.bits_of_float (float_of_string s)) (Int64.bits_of_float f)
        && String.exists (fun c -> c = '.' || c = 'e' || c = 'E') s
      else s = "null")

let%expect_test "json float property" =
  QCheck2.Test.check_exn ~rand:(Random.State.make [| 18 |]) float_round_trip;
  [%expect {||}]

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
