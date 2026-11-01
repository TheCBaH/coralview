The built-in platforms and the models their blocks allow:

  $ coralview platforms
  core-mini-axi (core-mini, CoreMiniAxi): commits, stalls, memory, axi, registers, traps
  core-mini-highmem-axi (core-mini, CoreMiniHighmemAxi): commits, stalls, memory, axi, registers, traps
  core-mini-itcm512kb-dtcm512kb-axi (core-mini, CoreMini_ITCM512KB_DTCM512KBAxi): commits, stalls, memory, axi, registers, traps
  rvv-core-mini-axi (rvv-core-mini, RvvCoreMiniAxi): commits, stalls, memory, axi, registers, ops, traps, vectors
  rvv-core-mini-highmem-axi (rvv-core-mini, RvvCoreMiniHighmemAxi): commits, stalls, memory, axi, registers, ops, traps, vectors
  rvv-core-mini-itcm512kb-dtcm512kb-axi (rvv-core-mini, RvvCoreMini_ITCM512KB_DTCM512KBAxi): commits, stalls, memory, axi, registers, ops, traps, vectors
  subsystem-vector-normal (subsystem, chip_verilator): dma
  subsystem-vector-highmem (subsystem, chip_verilator): dma
  subsystem-matrix-normal (subsystem, chip_verilator): dma
  subsystem-matrix-highmem (subsystem, chip_verilator): dma
  vme-core-mini-axi (vme-core-mini, VmeCoreMiniAxi): commits, stalls, memory, axi, registers, tiles, ops, traps, vectors

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
  window [0, end] pc 80000004: 1 commits, 1 cycles charged
  $ coralview commits --platform test-core.json --to-cycle 4 core.vcd
         4 0 80000000 02a00513 addi x10, x0, 42                 x10=0000002a       3   2   4
  root TOP.core: 8 cycles, 1 before the first dispatch, 2 later with nothing in flight; 0 retires without dispatch, 0 dispatches skipped, 0 values missing, 0 in flight at the end
  window [0, 4]: 1 commits, 4 cycles charged

A window also gives the totals of its own rows: the commits and cycles charged
inside it, and a profile whose shares are of those cycles. Without a window
none of this is printed:

  $ coralview commits --platform test-core.json --to-cycle 4 --profile 2 core.vcd
         4 0 80000000 02a00513 addi x10, x0, 42                 x10=0000002a       3   2   4
  root TOP.core: 8 cycles, 1 before the first dispatch, 2 later with nothing in flight; 0 retires without dispatch, 0 dispatches skipped, 0 values missing, 0 in flight at the end
  window [0, 4]: 1 commits, 4 cycles charged
        pc  count  cycles  share     d->r  instruction
  80000000      1       4 100.0%     3.00  addi x10, x0, 42
  $ coralview commits --platform test-core.json --pc 80000004 --profile 2 core.vcd
         5 0 80000004 00000013 addi x0, x0, 0                                      3   -   1
  root TOP.core: 8 cycles, 1 before the first dispatch, 2 later with nothing in flight; 0 retires without dispatch, 0 dispatches skipped, 0 values missing, 0 in flight at the end
  window [0, end] pc 80000004: 1 commits, 1 cycles charged
        pc  count  cycles  share     d->r  instruction
  80000004      1       1 100.0%     3.00  addi x0, x0, 0

A window can also run between two retirements, as the two reads of a cycle
counter around a kernel do: from the first retirement of the first PC to the
next of the second, both included. It is a first pass over the trace, and
the second PC has to retire after the first:

  $ coralview commits --platform test-core.json --between-pc 80000000,80000004 core.vcd
         4 0 80000000 02a00513 addi x10, x0, 42                 x10=0000002a       3   2   4
         5 0 80000004 00000013 addi x0, x0, 0                                      3   -   1
  root TOP.core: 8 cycles, 1 before the first dispatch, 2 later with nothing in flight; 0 retires without dispatch, 0 dispatches skipped, 0 values missing, 0 in flight at the end
  window [4, 5]: 2 commits, 5 cycles charged
  $ coralview commits --platform test-core.json --between-pc 80000004,80000004 core.vcd
  --between-pc: pc 80000004 never retires from cycle 5
  [3]
  $ coralview commits --platform test-core.json --between-pc 80000004,80000000 core.vcd
  --between-pc: pc 80000000 never retires from cycle 5
  [3]
  $ coralview commits --platform test-core.json --between-pc 90000000,80000000 core.vcd
  --between-pc: pc 90000000 retires fewer than 1 times
  [3]
  $ coralview commits --platform test-core.json --between-pc 80000000,80000004 --nth 2 core.vcd
  --between-pc: pc 80000000 retires fewer than 2 times
  [3]
  $ coralview commits --platform test-core.json --between-pc 80000000,80000004 - < core.vcd
  --between-pc reads the trace twice: name a file, not - or --exec
  [2]

The same retirements as JSON lines, filtered alike; the summary covers
the whole run:

  $ coralview commits --platform test-core.json --format jsonl core.vcd
  {"type":"coralview","schema_version":1,"model":"commits","platform":"test-core","trace":"core.vcd"}
  {"type":"commits.commit","lane":0,"instance":{"pc":2147483648,"word":44041491,"dispatched":1,"retired":4},"written":3,"dest":{"reg":10,"value":42},"store":false,"trap":false,"charged":4}
  {"type":"commits.commit","lane":0,"instance":{"pc":2147483652,"word":19,"dispatched":2,"retired":5},"store":false,"trap":false,"charged":1}
  {"type":"commits.summary","cycles":8,"before":1,"empty":2,"unmatched_retires":0,"skipped":0,"missing_values":0,"in_flight":0,"pending":[]}
  $ coralview commits --platform test-core.json --format jsonl --pc 80000004 core.vcd | jq -c 'select(.type == "commits.commit") | .instance'
  {"pc":2147483652,"word":19,"dispatched":2,"retired":5}

A saved JSONL gives back the profile, and the whole text; a platform that is not built in is given
again:

  $ coralview commits --platform test-core.json --format jsonl core.vcd > commits.jsonl
  $ coralview profile --platform test-core.json -n 2 commits.jsonl
        pc  count  cycles  share     d->r  instruction
  80000000      1       4  50.0%     3.00  addi x10, x0, 42
  80000004      1       1  12.5%     3.00  addi x0, x0, 0
  $ coralview commits --platform test-core.json --profile 2 core.vcd > commits.txt
  $ coralview render --platform test-core.json --profile 2 commits.jsonl | cmp - commits.txt

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

The retirements as a Kanata log for Konata, each instruction from its dispatch to its retirement:

  $ coralview run --platform test-core.json --kanata - core.vcd
  Kanata	0004
  C=	1
  I	0	0	0
  L	0	0	80000000 addi x10, x0, 42
  S	0	0	Ex
  C	1
  I	1	1	0
  L	1	0	80000004 addi x0, x0, 0
  S	1	0	Ex
  C	2
  E	0	0	Ex
  R	0	0	0
  C	1
  E	1	0	Ex
  R	1	1	0

In JSON lines the header says which window the rows are of; a whole-trace header has none:

  $ coralview commits --platform test-core.json --format jsonl --to-cycle 4 --pc 80000000 core.vcd | head -n 1
  {"type":"coralview","schema_version":1,"model":"commits","platform":"test-core","trace":"core.vcd","window":{"first":0,"last":4,"pcs":[2147483648]}}
  $ coralview commits --platform test-core.json --format jsonl --from-cycle 5 core.vcd | head -n 1
  {"type":"coralview","schema_version":1,"model":"commits","platform":"test-core","trace":"core.vcd","window":{"first":5,"pcs":[]}}
  $ coralview commits --platform test-core.json --format jsonl core.vcd | head -n 1
  {"type":"coralview","schema_version":1,"model":"commits","platform":"test-core","trace":"core.vcd"}

The profile by instruction class, from the trace and from its JSON lines (render takes the
words from the rows):

  $ coralview commits --platform test-core.json --profile 3 --profile-by class core.vcd | tail -n 2
  class         count  cycles  share     d->r
  alu               2       5  62.5%     3.00
  $ coralview commits --platform test-core.json --format jsonl core.vcd > core.jsonl
  $ coralview render --platform test-core.json --profile 3 --profile-by class core.jsonl | tail -n 2
  class         count  cycles  share     d->r
  alu               2       5  62.5%     3.00
