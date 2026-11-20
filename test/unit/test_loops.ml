open Coralview

let bne = 0xfe051ae3 (* bne x10, x0, <back> *)
let addi = 0x00150513
let jal_x0 = 0x0000006f
let jal_x1 = 0x000000ef
let mret = 0x30200073

let commit ?(word = Some addi) ?(trap = false) pc ~retired ~charged : Commits.commit =
  {
    lane = 0;
    pc;
    word;
    dispatched = None;
    written = None;
    retired;
    dest = None;
    store = false;
    trap;
    charged;
  }

(* PCs with their charges, retired a cycle apart. *)
let run l =
  List.mapi (fun i (pc, charged, word) -> commit ~word:(Some word) pc ~retired:(100 + i) ~charged) l

(* The same with the word and the trap flag of each retirement. *)
let run_t l =
  List.mapi (fun i (pc, charged, word, trap) -> commit ~word ~trap pc ~retired:(100 + i) ~charged) l

let print loops =
  List.iter
    (fun (l : Loops.loop) ->
      Printf.printf "loop %x tail %x%s trips %s\n" l.header l.tail
        (match l.parent with Some h -> Printf.sprintf " parent %x" h | None -> "")
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
    loop 8 tail c parent 4 trips 2/2@102 2/2@104 2/2@106 2/2@110 2/2@112
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

(* Two faults in straight-line code, each followed by a handler below it that returns. *)
let two_faults ~word ~trap =
  let fault pc = (pc, 1, word, trap) in
  Loops.detect
    (run_t
       [
         (0x20, 1, Some addi, false);
         fault 0x24;
         (0x04, 1, Some addi, false);
         (0x08, 1, Some mret, false);
         (0x28, 1, Some addi, false);
         fault 0x2c;
         (0x04, 1, Some addi, false);
         (0x08, 1, Some mret, false);
         (0x30, 1, Some addi, false);
       ])

let%expect_test "a trap after a branch is not a back edge to its handler" =
  List.iter
    (fun (name, loops) -> Printf.printf "%s: %d loops\n" name (List.length loops))
    [
      ("a branch that traps", two_faults ~word:(Some bne) ~trap:true);
      ("a decode fault, unmatched", two_faults ~word:None ~trap:true);
      ("an unmatched retire", two_faults ~word:None ~trap:false);
    ];
  [%expect
    {|
    a branch that traps: 0 loops
    a decode fault, unmatched: 0 loops
    an unmatched retire: 0 loops
    |}]

let%expect_test "an interrupted trip leaves the handler out" =
  (* The third retirement of 0x10 takes the trap; the handler is a PC below the loop. *)
  print
    (Loops.detect
       (run_t
          [
            (0x00, 1, Some addi, false);
            (0x10, 1, Some addi, false);
            (0x14, 1, Some bne, false);
            (0x10, 1, Some addi, true);
            (0x04, 5, Some addi, false);
            (0x08, 3, Some mret, false);
            (0x14, 1, Some bne, false);
            (0x10, 1, Some addi, false);
            (0x14, 1, Some bne, false);
            (0x18, 1, Some addi, false);
          ]));
  [%expect
    {|
    loop 10 tail 14 trips 2/2@101 2/2@103 2/2@107
      10 count 3 cycles 3
      14 count 3 cycles 3
    |}]

let%expect_test "a loop inside a handler has its own trips; the outer trip leaves it out" =
  print
    (Loops.detect
       (run_t
          [
            (0x10, 1, Some addi, false);
            (0x14, 1, Some bne, false);
            (0x10, 1, Some addi, true);
            (0x04, 4, Some addi, false);
            (0x08, 1, Some bne, false);
            (0x04, 1, Some addi, false);
            (0x08, 1, Some bne, false);
            (0x0c, 1, Some mret, false);
            (0x14, 1, Some bne, false);
            (0x10, 1, Some addi, false);
            (0x14, 1, Some bne, false);
            (0x18, 1, Some addi, false);
          ]));
  [%expect
    {|
    loop 4 tail 8 trips 2/5@103 2/2@105
      4 count 2 cycles 5
      8 count 2 cycles 2
    loop 10 tail 14 trips 2/2@100 2/2@102 2/2@109
      10 count 3 cycles 3
      14 count 3 cycles 3
    |}]
