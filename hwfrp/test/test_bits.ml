open Hwfrp
open Vcd_types

let%expect_test "widths around the native int boundary" =
  List.iter
    (fun w ->
      let b =
        if w > 62 then Bits.of_bytes_le ~width:w (Bytes.make 200 (Char.chr 255))
        else Bits.of_int ~width:w (-1)
      in
      let f = Bits.field b ~lo:(w / 2) ~width:(w - (w / 2)) in
      Printf.printf "%4d %s pop=%d field=%s int=%s\n" w
        (if w <= 72 then Bits.to_hex b else "...")
        (Bits.popcount b) (Bits.to_hex f)
        (match Bits.to_int b with Some _ -> "yes" | None -> "no"))
    [ 1; 24; 25; 53; 62; 63; 64; 65; 128; 1488 ];
  [%expect
    {|
       1 1 pop=1 field=1 int=yes
      24 ffffff pop=24 field=fff int=yes
      25 1ffffff pop=25 field=1fff int=yes
      53 1fffffffffffff pop=53 field=7ffffff int=yes
      62 3fffffffffffffff pop=62 field=7fffffff int=yes
      63 7fffffffffffffff pop=63 field=ffffffff int=no
      64 ffffffffffffffff pop=64 field=ffffffff int=no
      65 1ffffffffffffffff pop=65 field=1ffffffff int=no
     128 ... pop=128 field=ffffffffffffffff int=no
    1488 ... pop=1488 field=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff int=no |}]

let%expect_test
    "ovcd Bytes packing, against the record and against get_bits64 at byte-multiple widths" =
  List.iter
    (fun width ->
      let s = String.init width (fun i -> if i * 7 mod 3 = 0 || i mod 11 = 0 then '1' else '0') in
      let v = Vcd_ast.binary_value s in
      let b =
        match Logic.of_value ~width v with
        | Ok l -> Option.get (Logic.to_known l)
        | Error _ -> assert false
      in
      List.iter
        (fun (lo, w) ->
          let record = ref 0 in
          for k = lo + w - 1 downto lo do
            record := (!record lsl 1) lor if s.[width - 1 - k] = Char.chr 49 then 1 else 0
          done;
          let got = Bits.field_int b ~lo ~width:w in
          let ovcd =
            width mod 8 <> 0
            || Int64.equal (Int64.of_int got) (Value.get_bits64_exn v ~lo ~hi:(lo + w - 1))
          in
          Printf.printf "%d [%d+:%d] %x %s\n" width lo w got
            (if got = !record && ovcd then "ok" else "MISMATCH"))
        [ (0, 8); (3, 17); (37, 40); (60, 40); (90, 10) ])
    [ 100; 128 ];
  [%expect
    {|
    100 [0+:8] 49 ok
    100 [3+:17] 9349 ok
    100 [37+:40] 49249649a4 ok
    100 [60+:40] 9259269249 ok
    100 [90+:10] 249 ok
    128 [0+:8] d2 ok
    128 [3+:17] 1649a ok
    128 [37+:40] 9a4924b24d ok
    128 [60+:40] 2492c93492 ok
    128 [90+:10] 92 ok |}]

let%expect_test "four-state values" =
  List.iter
    (fun (w, v) ->
      match Logic.of_value ~width:w v with
      | Ok l -> Printf.printf "%d %s known=%b\n" w (Logic.to_string l) (Logic.is_known l)
      | Error e -> Format.printf "%d error: %a@." w Logic.pp_decode_error e)
    [
      (8, Value.Scalars [ X; B1; B0 ]);
      (8, Value.Scalars [ B1; Z ]);
      (6, Value.Scalars [ U; W; L; H; Dont_care; B1 ]);
      (4, Value.Scalar B1);
      (4, Value.Int 5);
      (66, Value.Bytes (Bytes.make 2 '\255'));
      (66, Value.Bytes (Bytes.of_string "\x03\x00\x00\x00\x00\x00\x00\x00\x01"));
      (66, Value.Bytes (Bytes.of_string "\x04\x00\x00\x00\x00\x00\x00\x00\x00"));
      (8, Value.Real 1.5);
    ];
  [%expect
    {|
    8 xxxxxx10 known=false
    8 0000001x known=false
    6 xxxhx1 known=false
    4 0001 known=true
    4 0101 known=true
    66 000000000000000000000000000000000000000000000000001111111111111111 known=true
    66 110000000000000000000000000000000000000000000000000000000000000001 known=true
    66 error: 9-byte value wider than its 66-bit signal
    8 error: not a bit vector: 1.5 |}]

let%expect_test "concat and compare" =
  let a = Bits.of_int ~width:4 0xa and b = Bits.of_int ~width:64 0x123 in
  let c = Bits.concat [ a; b ] in
  Printf.printf "%s %d %d %d\n" (Bits.to_hex c) (Bits.width c) (Bits.compare c c)
    (Bits.compare (Bits.of_int ~width:68 1) c);
  [%expect {| a0000000000000123 68 0 -1 |}]
