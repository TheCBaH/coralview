open Coralview
open Hwfrp

(* seek.fst has three blocks, [0,3], [3,7] and [7,11]: the second starts at a timestamp whose changes
   are in the first. [top/d] is first assigned in the last block, with the value its frame holds, and
   [top/a] repeats its value at the start of each block. *)
let file = "../signals.t/seek.fst"
let paths = [ "top/a"; "top/b"; "top/d" ]

let run ?path ~from ~changes paths =
  let out = ref [] in
  Hwfrp_native.with_file file (fun tr ->
      Signals.raw ?path tr paths ~from ~until:Int64.max_int ~changes (fun r ->
          out := Printf.sprintf "%Ld %s %s" r.time r.path (Signals.to_string r.value) :: !out));
  List.rev !out

let%expect_test "the seek starts at a block and gives the values before it" =
  let ids = ref [] in
  List.iter
    (fun time ->
      match
        Hwfrp_native.with_seek file ~time (fun state events ->
            ( Ovcd.Vcd.ID_map.cardinal state,
              match events () with
              | Seq.Cons (Ovcd.Ast.Timestamp t, _) -> Ovcd_types.Timestamp.to_int64 t
              | _ -> -1L ))
      with
      | Some (n, t) -> ids := Printf.sprintf "%Ld: %d values, from timestamp %Ld" time n t :: !ids
      | None -> ids := Printf.sprintf "%Ld: no seek" time :: !ids)
    [ 0L; 3L; 4L; 7L; 8L; 11L; 50L ];
  List.iter print_endline (List.rev !ids);
  [%expect
    {|
    0: no seek
    3: no seek
    4: 4 values, from timestamp 3
    7: 4 values, from timestamp 7
    8: 4 values, from timestamp 7
    11: 4 values, from timestamp 7
    50: 4 values, from timestamp 7 |}]

let%expect_test "raw from a time reads what the full scan reads" =
  let differ = ref [] and n = ref 0 in
  List.iter
    (fun ps ->
      for from = 0 to 12 do
        List.iter
          (fun changes ->
            incr n;
            if
              run ~path:file ~from:(Int64.of_int from) ~changes ps
              <> run ~from:(Int64.of_int from) ~changes ps
            then
              differ :=
                Printf.sprintf "%s from %d changes %b" (String.concat "," ps) from changes
                :: !differ)
          [ false; true ]
      done)
    [ paths; [ "top/a" ]; [ "top/d" ]; [ "top/b"; "top/a" ]; [ "top/clk"; "top/a"; "top/d" ] ];
  Printf.printf "%d runs, %d differ\n" !n (List.length !differ);
  List.iter print_endline !differ;
  [%expect {| 130 runs, 0 differ |}]

let%expect_test "a repeated value at a block boundary, and a first value equal to the frame's" =
  List.iter print_endline (run ~path:file ~from:5L ~changes:true paths);
  print_endline "--";
  List.iter print_endline (run ~path:file ~from:9L ~changes:true [ "top/d" ]);
  [%expect
    {|
    5 top/b 0x04
    6 top/a 0x07
    9 top/d 0bxxxxxxxx
    10 top/d 0xaa
    11 top/a 0x01
    --
    9 top/d 0bxxxxxxxx
    10 top/d 0xaa |}]
