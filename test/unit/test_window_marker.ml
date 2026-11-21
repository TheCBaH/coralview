open Coralview

let commit pc ?word retired : Commits.commit =
  {
    lane = 0;
    pc;
    word;
    dispatched = Some (retired - 1);
    written = None;
    retired;
    dest = None;
    store = false;
    trap = false;
    charged = 1;
  }

let ret = 0x00008067
let call = 0x008000ef
let symbols = Result.get_ok (Symbols.of_string Test_symbols.elf)

(* _start 0x10000..0x10010, kernel 0x10010..0x10030. The kernel calls a helper at 0x20000 and
   has a ret of its own at 0x10020, which the helper's does not reach. *)
let run =
  [
    commit 0x10000 5;
    commit 0x10010 8;
    commit 0x10014 ~word:call 9;
    commit 0x10020 ~word:ret 12;
    commit 0x10018 ~word:ret 15;
    commit 0x10000 20;
  ]

let show spec ?(nth = 1) ?(symbols = Some symbols) ?(window = Text.everything) commits =
  match Window_marker.make spec ~nth symbols with
  | Error (code, msg) -> Printf.printf "make: %d %s\n" code msg
  | Ok m -> (
      match Window_marker.resolve m window commits with
      | Ok w ->
          Printf.printf "[%d, %s]\n" w.first
            (if w.last = max_int then "end" else string_of_int w.last)
      | Error (code, msg) -> Printf.printf "%d %s\n" code msg)

let%expect_test "between two PCs, and the Nth start" =
  show (Between (0x10010, 0x10018)) run;
  show (Between (0x10000, 0x10018)) run;
  show (Between (0x10000, 0x10018)) ~nth:2 run;
  show (Between (0x10000, 0x10018)) ~nth:3 run;
  show (Between (0x10018, 0x10000)) run;
  show (Between (0x10018, 0x10000)) (List.filteri (fun i _ -> i < 5) run);
  [%expect
    {|
    [8, 15]
    [5, 15]
    3 --between-pc: pc 00010018 never retires from cycle 20
    3 --between-pc: pc 00010000 retires fewer than 3 times
    [15, 20]
    3 --between-pc: pc 00010000 never retires from cycle 15 |}]

let%expect_test "a function: the first ret inside it, or the ret that pops its frame" =
  show (Around "kernel") run;
  show (Entry "kernel") run;
  show (Entry "kernel") (List.filteri (fun i _ -> i < 3) run);
  show (Around "kernel") (List.filteri (fun i _ -> i < 3) run);
  show (Around "tail") run;
  [%expect
    {|
    [8, 12]
    [8, 15]
    [8, end]
    3 --around-symbol: a ret of kernel never retires from cycle 8
    3 --around-symbol: tail retires fewer than 1 times |}]

let%expect_test "the markers narrow the window given, and what is wrong with them is known first" =
  show (Between (0x10010, 0x10018)) ~window:{ Text.everything with first = 10; last = 14 } run;
  show (Around "kernel") ~symbols:None run;
  show (Entry "nosuch") run;
  [%expect
    {|
    [10, 14]
    make: 2 --around-symbol needs --elf
    make: 2 --entry: no function nosuch in the ELF |}]
