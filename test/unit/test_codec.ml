open Coralview

let diag_eq (a : Hwfrp.Diag.t) (b : Hwfrp.Diag.t) =
  a.severity = b.severity && a.source = b.source && a.code = b.code && a.cycle = b.cycle
  && Option.equal Vcd_types.Timestamp.equal a.time b.time
  && List.equal Vcd_types.Reference.equal a.paths b.paths
  && a.message = b.message

let%expect_test "shared codecs round-trip" =
  let rand = Random.State.make [| 2026 |] in
  List.iter (QCheck2.Test.check_exn ~rand)
    [
      Gen.roundtrip "span" Codec.span Gen.span;
      Gen.roundtrip "transaction" Codec.transaction Gen.transaction;
      Gen.roundtrip "instance" Instance.jsont Gen.instance;
      Gen.roundtrip "access" Access.jsont Gen.access;
      Gen.roundtrip ~eq:diag_eq "diag" Codec.diag Gen.diag;
      Gen.roundtrip ~eq:Hwfrp.Bits.equal "bits" Codec.bits Gen.bits;
    ];
  print_endline (Codec.to_line Codec.span { start = 3; stop = None });
  print_endline
    (Codec.to_line Access.jsont
       { address = 0x2000_0000; bytes = 4; write = true; region = Some "extmem" });
  print_endline
    (Codec.to_line Codec.diag
       (Hwfrp.Diag.make ~source:"bind" ~code:"bind.unknown-bits"
          ~paths:[ Vcd_types.Reference.of_list [ "TOP"; "x" ] ]
          "X bits"));
  [%expect
    {|
    {"start":3}
    {"address":536870912,"bytes":4,"write":true,"region":"extmem"}
    {"type":"diag","severity":"warning","source":"bind","code":"bind.unknown-bits","paths":["TOP.x"],"message":"X bits"} |}]
