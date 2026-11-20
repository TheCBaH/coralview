`commits` pairs each retirement with a dispatch by PC alone, taking the oldest queued dispatch of that
PC, and a retirement's value from the oldest unconsumed writeback to its destination register. The
fixtures are cycle lists for gen.sh (`d` dispatch, `w` write, `r` retire; PC, word and values in hex),
one cycle per line. Every cycle is charged to the oldest instruction in flight.

Retirements of one PC in consecutive cycles pair with the dispatches in order. `j .` at 0x100
dispatches three times and retires three times:

  $ bash gen.sh > same.vcd <<'END'
  > d 100 0000006f
  > d 100 0000006f
  > d 100 0000006f
  > r 100 7f
  > r 100 7f
  > r 100 7f
  > END
  $ coralview commits --platform commits-core.json same.vcd
  platform commits-core
     cycle L pc       word     instruction                      dest             d>r d>w chg
         3 0 00000100 0000006f jal x0, 0                                           3   -   4
         4 0 00000100 0000006f jal x0, 0                                           3   -   1
         5 0 00000100 0000006f jal x0, 0                                           3   -   1
  root TOP.core: 7 cycles, 0 before the first dispatch, 1 later with nothing in flight; 0 retires without dispatch, 0 dispatches skipped with 0 cycles charged, 0 values missing, 0 in flight at the end
  $ coralview commits --platform commits-core.json --format jsonl same.vcd | sh conserved.sh
  7 cycles = 6 retired + 0 in flight + 0 discarded + 0 before + 1 empty

Dispatches that no retirement matches are dropped when a younger one retires. Here 0x100 and 0x104
dispatch and never retire (squashed, say), then 0x108 dispatches and retires. The two dropped entries
are charged six cycles between them, which the summary carries as discarded:

  $ bash gen.sh > drop.vcd <<'END'
  > d 100 00100513
  > d 104 00200593
  > d 108 00000013
  > 
  > 
  > r 108 7f
  > END
  $ coralview commits --platform commits-core.json drop.vcd
  platform commits-core
     cycle L pc       word     instruction                      dest             d>r d>w chg
         5 0 00000108 00000013 addi x0, x0, 0                                      3   -   0
  root TOP.core: 7 cycles, 0 before the first dispatch, 1 later with nothing in flight; 0 retires without dispatch, 2 dispatches skipped with 6 cycles charged, 0 values missing, 0 in flight at the end
  $ coralview commits --platform commits-core.json --format jsonl drop.vcd | sh conserved.sh
  7 cycles = 0 retired + 0 in flight + 6 discarded + 0 before + 1 empty

A squashed dispatch of a PC that dispatches again pairs with the retirement of the second:

  $ bash gen.sh > squash.vcd <<'END'
  > d 100 00100513
  > d 104 00200593
  > 
  > 
  > d 100 00100513
  > d 104 00200593
  > r 100 7f
  > r 104 7f
  > END
  $ coralview commits --platform commits-core.json squash.vcd
  platform commits-core
     cycle L pc       word     instruction                      dest             d>r d>w chg
         6 0 00000100 00100513 addi x10, x0, 1                                     6   -   7
         7 0 00000104 00200593 addi x11, x0, 2                                     6   -   1
  root TOP.core: 9 cycles, 0 before the first dispatch, 0 later with nothing in flight; 0 retires without dispatch, 0 dispatches skipped with 0 cycles charged, 0 values missing, 2 in flight at the end
  in flight at the end, oldest first:
    dispatched        4 pc 00000100 00100513 addi x10, x0, 1
    dispatched        5 pc 00000104 00200593 addi x11, x0, 2
  $ coralview commits --platform commits-core.json --format jsonl squash.vcd | sh conserved.sh
  9 cycles = 8 retired + 1 in flight + 0 discarded + 0 before + 0 empty

Squashed dispatches passed over by the retirements of the real ones, here of the same PC and of
another, are discarded the same way:

  $ bash gen.sh > passed.vcd <<'END'
  > d 100 00100513
  > d 104 00200593
  > 
  > d 108 00000013
  > d 100 00100513
  > r 108 7f
  > r 100 7f
  > END
  $ coralview commits --platform commits-core.json passed.vcd
  platform commits-core
     cycle L pc       word     instruction                      dest             d>r d>w chg
         5 0 00000108 00000013 addi x0, x0, 0                                      2   -   0
         6 0 00000100 00100513 addi x10, x0, 1                                     2   -   1
  root TOP.core: 8 cycles, 0 before the first dispatch, 1 later with nothing in flight; 0 retires without dispatch, 2 dispatches skipped with 6 cycles charged, 0 values missing, 0 in flight at the end
  $ coralview commits --platform commits-core.json --format jsonl passed.vcd | sh conserved.sh
  8 cycles = 1 retired + 0 in flight + 6 discarded + 0 before + 1 empty

A retirement with no dispatch for its PC leaves the queue as it is:

  $ bash gen.sh > unmatched.vcd <<'END'
  > d 100 00000013
  > r 300 7f
  > r 100 7f
  > r 100 7f
  > END
  $ coralview commits --platform commits-core.json unmatched.vcd
  platform commits-core
     cycle L pc       word     instruction                      dest             d>r d>w chg
         1 0 00000300 ???????? ?                                                   -   -   0
         2 0 00000100 00000013 addi x0, x0, 0                                      2   -   3
         3 0 00000100 ???????? ?                                                   -   -   0
  root TOP.core: 5 cycles, 0 before the first dispatch, 2 later with nothing in flight; 2 retires without dispatch, 0 dispatches skipped with 0 cycles charged, 0 values missing, 0 in flight at the end
  $ coralview commits --platform commits-core.json --format jsonl unmatched.vcd | sh conserved.sh
  5 cycles = 3 retired + 0 in flight + 0 discarded + 0 before + 2 empty

A write nobody retires on leaves every later value of its register one retirement late:

  $ bash gen.sh > surplus.vcd <<'END'
  > d 100 00100513
  > d 104 00150513
  > d 108 00150513
  > w a 1
  > w a 2
  > r 100 a
  > w a 3
  > r 104 a
  > r 108 a
  > END
  $ coralview commits --platform commits-core.json surplus.vcd
  platform commits-core
     cycle L pc       word     instruction                      dest             d>r d>w chg
         5 0 00000100 00100513 addi x10, x0, 1                  x10=00000001       5   3   6
         7 0 00000104 00150513 addi x10, x10, 1                 x10=00000002       6   3   2
         8 0 00000108 00150513 addi x10, x10, 1                 x10=00000003       6   4   1
  root TOP.core: 10 cycles, 0 before the first dispatch, 1 later with nothing in flight; 0 retires without dispatch, 0 dispatches skipped with 0 cycles charged, 0 values missing, 0 in flight at the end
  $ coralview commits --platform commits-core.json --format jsonl surplus.vcd | sh conserved.sh
  10 cycles = 9 retired + 0 in flight + 0 discarded + 0 before + 1 empty

A trapping retirement flushes the pipeline: the instructions dispatched behind it never retire, and nor
do the values they wrote. A store faults at 0x100, the load at 0x104 and the `addi x12, x0, 7` at 0x108
are dispatched behind it and the addi writes back before the flush. The handler at 0x300 and then the
re-executed 0x108 write x12 as well:

  $ bash gen.sh > trap.vcd <<'END'
  > d 100 00072023
  > d 104 0007a683
  > d 108 00700613
  > w c 7
  > 
  > x 100 7f
  > 
  > 
  > 
  > d 300 00100613
  > w c 1
  > r 300 c
  > d 108 00700613
  > w c 7
  > r 108 c
  > END
  $ coralview commits --platform commits-core.json trap.vcd
  platform commits-core
     cycle L pc       word     instruction                      dest             d>r d>w chg
         5 0 00000100 00072023 sw x0, 0(x14)                                       5   -   6  TRAP
        11 0 00000300 00100613 addi x12, x0, 1                  x12=00000001       2   1   3
        14 0 00000108 00700613 addi x12, x0, 7                  x12=00000007       2   1   3
  root TOP.core: 16 cycles, 0 before the first dispatch, 4 later with nothing in flight; 0 retires without dispatch, 2 dispatches skipped with 0 cycles charged, 0 values missing, 0 in flight at the end
  $ coralview commits --platform commits-core.json --format jsonl trap.vcd | sh conserved.sh
  16 cycles = 12 retired + 0 in flight + 0 discarded + 0 before + 4 empty

A handler that starts at the PC of a squashed dispatch pairs with its own dispatch, not the squashed one:

  $ bash gen.sh > trap-pc.vcd <<'END'
  > d 100 00072023
  > d 104 0007a683
  > 
  > x 100 7f
  > 
  > 
  > 
  > d 104 0007a683
  > w d 5
  > r 104 d
  > END
  $ coralview commits --platform commits-core.json trap-pc.vcd
  platform commits-core
     cycle L pc       word     instruction                      dest             d>r d>w chg
         3 0 00000100 00072023 sw x0, 0(x14)                                       3   -   4  TRAP
         9 0 00000104 0007a683 lw x13, 0(x15)                   x13=00000005       2   1   3
  root TOP.core: 11 cycles, 0 before the first dispatch, 4 later with nothing in flight; 0 retires without dispatch, 1 dispatches skipped with 0 cycles charged, 0 values missing, 0 in flight at the end
  $ coralview commits --platform commits-core.json --format jsonl trap-pc.vcd | sh conserved.sh
  11 cycles = 7 retired + 0 in flight + 0 discarded + 0 before + 4 empty
