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

module Pt = struct
  let name = "pt"

  module Event = struct
    type t = { x : int }

    let jsont =
      Codec.record "pt.p" (fun x -> { x })
      |> Jsont.Object.mem "x" Jsont.int ~enc:(fun e -> e.x)
      |> Jsont.Object.finish
  end
end

let pt = (module Pt : Output.OUTPUT with type Event.t = Pt.Event.t)

let header_line =
  Codec.to_line Jsonl.header_jsont (Jsonl.header ~model:"pt" ~platform:"p" ~trace:"t")

let diag_line code = Codec.to_line Codec.diag (Hwfrp.Diag.make ~source:"pt" ~code "d")
let report = function Ok (e : Pt.Event.t) -> Printf.printf "event %d\n" e.x | Error _ -> ()

let dump (r : Pt.Event.t Jsonl.reader) =
  Printf.printf "header %s; diags %s; errors %d\n"
    (match r.header () with Some h -> h.model | None -> "-")
    (String.concat "," (List.map (fun (d : Hwfrp.Diag.t) -> d.code) (r.diags ())))
    (List.length (r.errors ()))

let%expect_test "a saved file: header, events, diagnostics, summary" =
  let r =
    Jsonl.reader pt
      (List.to_seq
         [
           header_line;
           {|{"type":"pt.p","x":1}|};
           diag_line "a";
           {|{"type":"pt.p","x":2}|};
           diag_line "b";
           {|{"type":"pt.summary","n":2}|};
         ])
  in
  dump r;
  (match r.events () with
  | Seq.Cons (e, _) ->
      report e;
      dump r
  | Nil -> ());
  r.finish ();
  r.finish ();
  dump r;
  print_endline (string_of_bool (List.of_seq r.events = []));
  [%expect
    {|
    header -; diags ; errors 0
    event 1
    header pt; diags ; errors 0
    header pt; diags a,b; errors 0
    true |}]

let%expect_test "event lines alone" =
  let r = Jsonl.reader pt (List.to_seq [ {|{"type":"pt.p","x":7}|}; {|{"type":"pt.p","x":8}|} ]) in
  Seq.iter report r.events;
  dump r;
  [%expect {|
    event 7
    event 8
    header -; diags ; errors 0 |}]

let%expect_test "an error does not end the stream and a trailing one is kept" =
  let r =
    Jsonl.reader pt
      (List.to_seq
         [
           {|{"type":"pt.p","x":1}|};
           "{";
           {|{"type":"pt.p","x":2}|};
           {|{"type":"pt.q"}|};
           {|{"type":"pt.summaryx"}|};
         ])
  in
  Seq.iter
    (function
      | Error m -> print_endline ("error " ^ List.hd (String.split_on_char (Char.chr 10) m))
      | ok -> report ok)
    r.events;
  dump r;
  let r = Jsonl.reader pt (List.to_seq [ {|{"type":"pt.p","x":1}|}; "}" ]) in
  (match r.events () with Seq.Cons (e, _) -> report e | _ -> ());
  Printf.printf "before finish: %d\n" (List.length (r.errors ()));
  r.finish ();
  Printf.printf "after finish: %d\n" (List.length (r.errors ()));
  [%expect
    {|
    event 1
    error Unclosed line object
    event 2
    error Unexpected type enum string value: pt.q. Should it be pt.p ?
    error Unexpected type enum string value: pt.summaryx. Must be pt.p.
    header -; diags ; errors 3
    event 1
    before finish: 0
    after finish: 1 |}]

let%expect_test "from a channel" =
  let file = Filename.temp_file "pt" ".jsonl" in
  Out_channel.with_open_text file (fun oc ->
      output_string oc (header_line ^ "\n{\"type\":\"pt.p\",\"x\":5}\n"));
  In_channel.with_open_text file (fun ic ->
      let r = Jsonl.reader pt (Jsonl.channel_lines ic) in
      Seq.iter report r.events;
      dump r);
  Sys.remove file;
  [%expect {|
    event 5
    header pt; diags ; errors 0 |}]
