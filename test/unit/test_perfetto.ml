open Coralview

let%expect_test "write takes the slices and the counters as sequences, pulled once in order" =
  let pulled = ref [] in
  let tap name seq =
    Seq.map
      (fun x ->
        pulled := name :: !pulled;
        x)
      seq
  in
  let slice track start : Perfetto.slice = { track; name = "s"; start; stop = start; args = [] } in
  let counter cycle : Perfetto.counter = { c_track = "c"; cycle; value = 1 } in
  let file = Filename.temp_file "perfetto" ".json" in
  let oc = open_out_bin file in
  Perfetto.write oc
    [
      {
        process = "p";
        slices = tap "slice" (List.to_seq [ slice "a" 1; slice "b" 2 ]);
        counters = tap "counter" (List.to_seq [ counter 3 ]);
      };
    ];
  close_out oc;
  print_string (In_channel.with_open_bin file In_channel.input_all);
  Sys.remove file;
  print_endline (String.concat " " (List.rev !pulled));
  [%expect
    {|
    {"displayTimeUnit":"ns","traceEvents":[
    {"ph":"M","pid":1,"name":"process_name","args":{"name":"p"}},
    {"ph":"M","pid":1,"tid":1,"name":"thread_name","args":{"name":"a"}},
    {"ph":"X","pid":1,"tid":1,"name":"s","ts":1,"dur":1,"args":{}},
    {"ph":"M","pid":1,"tid":2,"name":"thread_name","args":{"name":"b"}},
    {"ph":"X","pid":1,"tid":2,"name":"s","ts":2,"dur":1,"args":{}},
    {"ph":"C","pid":1,"name":"c","ts":3,"args":{"value":1}}
    ]}
    slice slice counter |}]
