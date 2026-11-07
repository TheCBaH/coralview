open Coralview

let bne = 0xfe051ae3 (* bne x10, x0, <back> *)
let addi = 0x00150513
let jal_x0 = 0x0000006f
let jal_x1 = 0x000000ef

let commit ?(word = addi) pc ~retired ~charged : Commits.commit =
  {
    lane = 0;
    pc;
    word = Some word;
    dispatched = None;
    written = None;
    retired;
    dest = None;
    store = false;
    trap = false;
    charged;
  }

(* PCs with their charges, retired a cycle apart. *)
let run l = List.mapi (fun i (pc, charged, word) -> commit ~word pc ~retired:(100 + i) ~charged) l

let print loops =
  List.iter
    (fun (l : Loops.loop) ->
      Printf.printf "loop %x tail %x trips %s\n" l.header l.tail
        (String.concat " "
           (List.map
              (fun (t : Loops.trip) -> Printf.sprintf "%d/%d@%d" t.instructions t.cycles t.start)
              l.trips));
      List.iter
        (fun (p : Loops.pc_stat) -> Printf.printf "  %x count %d cycles %d\n" p.pc p.count p.cycles)
        l.body)
    loops

let%expect_test "a loop whose first trip is slow" =
  (* Three trips of two instructions; the first waits 20 cycles on a cold load. *)
  print
    (Loops.detect
       (run
          [
            (0x00, 1, addi);
            (0x10, 20, addi);
            (0x14, 4, bne);
            (0x10, 3, addi);
            (0x14, 2, bne);
            (0x10, 3, addi);
            (0x14, 2, bne);
            (0x18, 1, addi);
          ]));
  [%expect
    {|
    loop 10 tail 14 trips 2/24@101 2/5@103 2/5@105
      10 count 3 cycles 26
      14 count 3 cycles 8
    |}]

let%expect_test "nested loops each have their trips; the outer contains the inner" =
  print
    (Loops.detect
       (run
          [
            (0x00, 1, addi);
            (0x04, 1, addi);
            (0x08, 1, addi);
            (0x0c, 1, bne) (* inner back edge to 0x08 *);
            (0x08, 1, addi);
            (0x0c, 1, bne);
            (0x08, 1, addi);
            (0x0c, 1, addi);
            (0x10, 1, bne) (* outer back edge to 0x04 *);
            (0x04, 1, addi);
            (0x08, 1, addi);
            (0x0c, 1, bne);
            (0x08, 1, addi);
            (0x0c, 1, addi);
            (0x10, 1, bne);
            (0x14, 1, addi);
          ]));
  [%expect
    {|
    loop 4 tail 10 trips 8/8@101 6/6@109
      4 count 2 cycles 2
      8 count 5 cycles 5
      c count 5 cycles 5
      10 count 2 cycles 2
    loop 8 tail c trips 2/2@102 2/2@104 2/2@106 2/2@110 2/2@112
      8 count 5 cycles 5
      c count 5 cycles 5 |}]

let%expect_test "a backward call and a forward jump are not loops" =
  print
    (Loops.detect
       (run
          [
            (0x10, 1, addi);
            (0x14, 1, bne) (* taken back to 0x10 *);
            (0x10, 1, addi);
            (0x14, 1, addi) (* falls through: the last trip *);
            (0x18, 1, jal_x1) (* a call to an earlier function *);
            (0x00, 1, addi);
            (0x04, 1, jal_x0) (* forward jump *);
            (0x20, 1, addi);
          ]));
  [%expect
    {|
    loop 10 tail 14 trips 2/2@100 2/2@102
      10 count 2 cycles 2
      14 count 2 cycles 2 |}]
