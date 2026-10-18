The built-in platforms and the models their blocks allow:

  $ coralview platforms
  core-mini-axi (core-mini, CoreMiniAxi): commits, stalls, memory, axi, registers, traps
  core-mini-highmem-axi (core-mini, CoreMiniHighmemAxi): commits, stalls, memory, axi, registers, traps
  core-mini-itcm512kb-dtcm512kb-axi (core-mini, CoreMini_ITCM512KB_DTCM512KBAxi): commits, stalls, memory, axi, registers, traps
  rvv-core-mini-axi (rvv-core-mini, RvvCoreMiniAxi): commits, stalls, memory, axi, registers, traps, vectors
  rvv-core-mini-highmem-axi (rvv-core-mini, RvvCoreMiniHighmemAxi): commits, stalls, memory, axi, registers, traps, vectors
  rvv-core-mini-itcm512kb-dtcm512kb-axi (rvv-core-mini, RvvCoreMini_ITCM512KB_DTCM512KBAxi): commits, stalls, memory, axi, registers, traps, vectors
  subsystem-vector-normal (subsystem, chip_verilator): dma
  subsystem-vector-highmem (subsystem, chip_verilator): dma
  subsystem-matrix-normal (subsystem, chip_verilator): dma
  subsystem-matrix-highmem (subsystem, chip_verilator): dma
  vme-core-mini-axi (vme-core-mini, VmeCoreMiniAxi): commits, stalls, memory, axi, registers, tiles, traps, vectors

A platform description for a one-lane test core. Every signal its blocks
imply is in core.vcd:

  $ coralview check --platform test-core.json core.vcd
  commits at TOP.core
    bound   io_aclk 1: core clock
    bound   io_debug_dispatch_0_instFire 1: dispatch lane fires
    bound   io_debug_dispatch_0_instAddr 32: dispatched PC
    bound   io_debug_dispatch_0_instInst 32: dispatched word
    bound   io_debug_regfile_writeData_0_valid 1: regfile writeback
    bound   io_debug_regfile_writeData_0_bits_addr 5: written register
    bound   io_debug_regfile_writeData_0_bits_data 32: written value
    bound   io_debug_rb_inst_0_valid 1: retirement lane valid
    bound   io_debug_rb_inst_0_bits_pc 32: retired PC
    bound   io_debug_rb_inst_0_bits_idx 7: retired destination index
    bound   io_debug_rb_inst_0_bits_trap 1: retired with a trap

Two instructions dispatched in cycles 1 and 2; x10 is written back in cycle 3,
then they retire in cycles 4 and 5, the second without a destination:

  $ coralview commits --platform test-core.json --profile 2 core.vcd
         4 0 80000000 02a00513 addi x10, x0, 42                 x10=0000002a       3   2   4
         5 0 80000004 00000013 addi x0, x0, 0                                      3   -   1
  root TOP.core: 8 cycles, 1 before the first dispatch, 2 later with nothing in flight; 0 retires without dispatch, 0 dispatches skipped, 0 values missing, 0 in flight at the end
        pc  count  cycles  share     d->r  instruction
  80000000      1       4  50.0%     3.00  addi x10, x0, 42
  80000004      1       1  12.5%     3.00  addi x0, x0, 0

Rows can be selected by cycle and PC; the totals still cover the whole
run:

  $ coralview commits --platform test-core.json --pc 80000004 core.vcd
         5 0 80000004 00000013 addi x0, x0, 0                                      3   -   1
  root TOP.core: 8 cycles, 1 before the first dispatch, 2 later with nothing in flight; 0 retires without dispatch, 0 dispatches skipped, 0 values missing, 0 in flight at the end
  $ coralview commits --platform test-core.json --to-cycle 4 core.vcd
         4 0 80000000 02a00513 addi x10, x0, 42                 x10=0000002a       3   2   4
  root TOP.core: 8 cycles, 1 before the first dispatch, 2 later with nothing in flight; 0 retires without dispatch, 0 dispatches skipped, 0 values missing, 0 in flight at the end

A trace without the register writeback ports does not match the
description, which is a hard error:

  $ coralview commits --platform test-core.json partial.vcd
  platform test-core does not match the trace (model commits):
    missing io_debug_regfile_writeData_0_valid: regfile writeback
  [3]

Nor does a valid signal of the wrong width:

  $ coralview check --platform test-core.json wide.vcd
  platform test-core does not match the trace (model commits):
    width   io_debug_rb_inst_0_valid 2, expected 1: retirement lane valid
  [3]

The description has no dispatch block, so there is no stall model:

  $ coralview stalls --platform test-core.json core.vcd
  platform test-core describes no dispatch block
  [2]

Unknown members in a description are errors:

  $ coralview check --platform typo.json core.vcd
  Unexpected member fetch for dispatch_debug object
  File "typo.json", line 10, characters 57-58:
  File "typo.json": in member dispatch_debug of
  File "typo.json", lines 9-10, characters 12-58: blocks object
  File "typo.json": in member blocks of
  File "typo.json", lines 1-10, characters 0-58: platform object
  [2]

Command-line errors are cmdliner's, with its exit status:

  $ coralview commits core.vcd
  Usage: coralview commits [--help] [OPTION]… FILE
  coralview: required option --platform is missing
  [124]
