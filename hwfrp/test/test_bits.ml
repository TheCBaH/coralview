open Hwfrp
open Ovcd_types

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
      let v = Ovcd.Ast.binary_value s in
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

(* The byte-wise paths against bit-at-a-time references built on [Bits.bit]. *)
let%expect_test "word-wise paths against bit-at-a-time references" =
  let seed = ref 12345 in
  let rnd n =
    seed := ((!seed * 1103515245) + 12345) land 0x3fffffff;
    (!seed lsr 8) mod n
  in
  let bits_of t = List.init (Bits.width t) (Bits.bit t) in
  let of_bits l =
    let w = List.length l in
    let b = Bytes.make ((w + 7) / 8) '\000' in
    List.iteri
      (fun k x ->
        if x then Bytes.set_uint8 b (k / 8) (Bytes.get_uint8 b (k / 8) lor (1 lsl (k mod 8))))
      l;
    Bits.of_bytes_le ~width:w b
  in
  let sub l lo w = List.filteri (fun k _ -> k >= lo && k < lo + w) l in
  let value l = List.fold_right (fun x r -> (r lsl 1) lor if x then 1 else 0) l 0 in
  let random w =
    let b = Bytes.init (((w + 7) / 8) + 1) (fun _ -> Char.chr (rnd 256)) in
    (* Sparse and dense patterns both. *)
    if rnd 3 = 0 then Bytes.fill b 0 (Bytes.length b) (if rnd 2 = 0 then '\000' else '\255');
    if rnd 4 = 0 then Bytes.set_uint8 b (rnd (Bytes.length b)) (1 lsl rnd 8);
    Bits.of_bytes_le ~width:w b
  in
  let widths = [| 1; 7; 8; 9; 31; 32; 33; 61; 62; 63; 64; 65; 69; 70; 71; 127; 128; 129; 200 |] in
  let bad = ref 0 and n = ref 0 in
  let check name ok =
    incr n;
    if not ok then begin
      incr bad;
      Printf.printf "MISMATCH %s\n" name
    end
  in
  for _ = 1 to 3000 do
    let w = widths.(rnd (Array.length widths)) in
    let t = random w in
    let l = bits_of t in
    let lo = rnd w in
    let fw = rnd (w - lo + 1) in
    let f = Bits.field t ~lo ~width:fw in
    check "field" (Bits.width f = fw && bits_of f = sub l lo fw);
    if fw <= 62 then check "field_int" (Bits.field_int t ~lo ~width:fw = value (sub l lo fw));
    check "popcount" (Bits.popcount t = List.length (List.filter Fun.id l));
    check "is_zero" (Bits.is_zero t = not (List.mem true l));
    check "to_int"
      (Bits.to_int t
      = if List.mem true (sub l 62 (max 0 (w - 62))) then None else Some (value (sub l 0 62)));
    check "to_int64"
      (Bits.to_int64 t
      =
      if List.mem true (sub l 64 (max 0 (w - 64))) then None
      else
        Some
          (List.fold_right
             (fun x r -> Int64.logor (Int64.shift_left r 1) (if x then 1L else 0L))
             (sub l 0 64) 0L));
    let u = random widths.(rnd (Array.length widths)) in
    let parts = [ t; u; f ] in
    check "concat" (bits_of (Bits.concat parts) = List.concat_map bits_of (List.rev parts));
    check "equal"
      (Bits.equal t t && Bits.equal t (of_bits l) && Bits.equal t u = (bits_of t = bits_of u));
    check "compare"
      (Bits.compare t u
      =
      if w <> Bits.width u then Int.compare w (Bits.width u)
      else Stdlib.compare (List.rev l) (List.rev (bits_of u)))
  done;
  Printf.printf "%d checks, %d mismatches\n" !n !bad;
  [%expect {| 26860 checks, 0 mismatches |}]

let%expect_test "Bitset.iter visits the set bits in ascending order" =
  let n = 300 in
  let s = Bitset.create n in
  let seen = ref [] in
  Bitset.iter (fun i -> seen := i :: !seen) s;
  Printf.printf "empty: %d\n" (List.length !seen);
  List.iter (Bitset.add s) [ 0; 1; 61; 62; 63; 123; 124; 186; 299; 150 ];
  Printf.printf "%s\n" (String.concat "," (List.map string_of_int (Bitset.elements s)));
  let all = Bitset.create n in
  for i = 0 to n - 1 do
    Bitset.add all i
  done;
  Printf.printf "%b\n" (Bitset.elements all = List.init n Fun.id);
  [%expect {|
    empty: 0
    0,1,61,62,63,123,124,150,186,299
    true |}]
