A reset member names the core's reset signal and the level that asserts it.
The trace here (reset.vcd, made by gen.sh) holds the platform.t trace after two cycles of reset, during
which its values are unknown or garbage: a dispatch fires, an instruction
retires, a register is written. A description without a reset reads them as
they are, a retirement that was never dispatched and unknown bits included:

  $ grep -v '"reset"' reset.json > plain.json
  $ coralview commits --platform plain.json reset.vcd
  platform test-core
     cycle L pc       word     instruction                      dest             d>r d>w chg
         1 0 00004000 ???????? ?                                x5=?               -   -   0
         7 0 80000000 02a00513 addi x10, x0, 42                 x10=0000002a       3   2   0
         8 0 80000004 00000013 addi x0, x0, 0                                      3   -   1
  root TOP.core: 11 cycles, 0 before the first dispatch, 2 later with nothing in flight; 1 retires without dispatch, 1 dispatches skipped with 8 cycles charged, 1 values missing, 0 in flight at the end
  $ coralview commits --platform plain.json --format jsonl reset.vcd | jq -c 'select(.type == "diag") | [.code, .cycle, .paths[0]]'
  ["bind.unknown-bits",0,"TOP.core.io_debug_regfile_writeData_0_bits_addr"]
  ["bind.unknown-bits",0,"TOP.core.io_debug_regfile_writeData_0_bits_data"]
  ["bind.unknown-bits",0,"TOP.core.io_debug_rb_inst_0_bits_pc"]
  ["bind.unknown-bits",0,"TOP.core.io_debug_rb_inst_0_bits_idx"]
  ["bind.unknown-bits",0,"TOP.core.io_debug_rb_inst_0_bits_trap"]

With the reset, the two cycles in it are not read: no lane is valid in them and
the unknown values are not reported. The cycles are still counted, and charged
to the first instruction as the cycles before it:

  $ coralview commits --platform reset.json reset.vcd
  platform test-core
     cycle L pc       word     instruction                      dest             d>r d>w chg
         7 0 80000000 02a00513 addi x10, x0, 42                 x10=0000002a       3   2   4
         8 0 80000004 00000013 addi x0, x0, 0                                      3   -   1
  root TOP.core: 11 cycles, 4 before the first dispatch, 2 later with nothing in flight; 0 retires without dispatch, 0 dispatches skipped with 0 cycles charged, 0 values missing, 0 in flight at the end
  $ coralview commits --platform reset.json --format jsonl reset.vcd | jq -c 'select(.type == "diag")'

The reset is a bound signal like the clock:

  $ coralview check --platform reset.json reset.vcd | head -4
  platform test-core
  commits at TOP.core
    bound   io_aclk 1: core clock
    bound   io_aresetn 1: reset

A high-level reset is the same trace with the signal inverted:

  $ sed -e 's/^0R$/9R/' -e 's/^1R$/0R/' -e 's/^9R$/1R/' reset.vcd > inverted.vcd
  $ sed 's/"active": "low"/"active": "high"/' reset.json > high.json
  $ coralview commits --platform high.json inverted.vcd > high.txt
  $ coralview commits --platform reset.json reset.vcd | cmp - high.txt

A trace that never leaves reset has no cycles to read, which is reported:

  $ sed 's/^1R$/0R/' reset.vcd > held.vcd
  $ coralview commits --platform reset.json --format jsonl held.vcd | jq -c 'select(.type == "diag" or .type == "commits.commit")'
  {"type":"diag","severity":"warning","source":"io_aclk","code":"clock.always-in-reset","cycle":10,"time":22,"paths":[],"message":"the reset was asserted at all 11 clock samples"}

The signal must exist in the trace, as the clock must:

  $ sed 's/io_aresetn/io_rst_n/' reset.json > gone.json
  $ coralview commits --platform gone.json reset.vcd
  platform test-core does not match the trace (model commits):
    missing io_rst_n: reset
  [3]

Errors in the member are reported at it, with the file and line:

  $ sed 's/"active": "low"/"active": "down"/' reset.json > down.json
  $ coralview check --platform down.json reset.vcd
  Unexpected reset level enum string value: down. Should it be low ?
  File "down.json", line 8, characters 47-53:
  File "down.json", line 8, characters 37-45: in member active of
  File "down.json", line 8, characters 11-55: reset object
  File "down.json", line 8, characters 2-9: in member reset of
  File "down.json", lines 1-19, characters 0-1: platform object
  [2]
  $ sed 's/"signal": "io_aresetn"/"signal": ""/' reset.json > unnamed.json
  $ coralview check --platform unnamed.json reset.vcd
  reset: the signal has no name
  File "unnamed.json", line 8, characters 11-44:
  File "unnamed.json", line 8, characters 2-9: in member reset of
  File "unnamed.json", lines 1-19, characters 0-1: platform object
  [2]
  $ sed 's/"active": "low"/"level": "low"/' reset.json > level.json
  $ coralview check --platform level.json reset.vcd
  Unexpected member level for reset object
  File "level.json", line 8, characters 11-53:
  File "level.json", line 8, characters 2-9: in member reset of
  File "level.json", lines 1-19, characters 0-1: platform object
  [2]
