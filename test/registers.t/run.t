Two instructions write x1 and x2: each is announced when it dispatches (the marks), written back,
stored in the register file one sample later and retired. The pipeline flushes in cycle 4. The
register file, the scoreboards and the retirements agree:

  $ coralview registers --platform reg-core.json registers.vcd
  platform reg-core
  root TOP.core: 7 cycles
  registers.storage                 2 comparisons, 0 failures
  registers.scoreboard             69 comparisons, 0 failures
  registers.flushed                69 comparisons, 0 failures
  registers.architectural           2 comparisons, 0 failures
  1 pipeline flushes
  storage at the end:
    x1   0000002a  x2   00000007  x3   00000000  f0   00000000

As JSON lines: every register at the first sample (the initial state), each change of the
storage, each flush, and at the end the comparisons made over the whole trace:

  $ coralview registers --platform reg-core.json --format jsonl registers.vcd | grep -v '"type":"registers.summary"'
  {"type":"coralview","schema_version":3,"model":"registers","platform":"reg-core","trace":"registers.vcd"}
  {"type":"registers.write","cycle":0,"reg":1,"value":0}
  {"type":"registers.write","cycle":0,"reg":2,"value":0}
  {"type":"registers.write","cycle":0,"reg":3,"value":0}
  {"type":"registers.write","cycle":0,"reg":32,"value":0}
  {"type":"registers.write","cycle":2,"reg":1,"value":42}
  {"type":"registers.write","cycle":3,"reg":2,"value":7}
  {"type":"registers.flush","cycle":4,"file":"x"}
  {"type":"registers.checks","cycle":6,"relations":[{"code":"registers.storage","comparisons":2,"failures":0},{"code":"registers.scoreboard","comparisons":69,"failures":0},{"code":"registers.flushed","comparisons":69,"failures":0},{"code":"registers.architectural","comparisons":2,"failures":0}]}

bad.vcd stores 9 in x2 where 7 was written back and retired:

  $ coralview registers --platform reg-core.json bad.vcd
  platform reg-core
  root TOP.core: 7 cycles
  registers.storage                 2 comparisons, 1 failures
  registers.scoreboard             69 comparisons, 0 failures
  registers.flushed                69 comparisons, 0 failures
  registers.architectural           2 comparisons, 1 failures
  1 pipeline flushes
  storage at the end:
    x1   0000002a  x2   00000009  x3   00000000  f0   00000000
  architectural values that differ from storage at the end:
    x2   00000007
  error[registers.storage] registers cycle 3 time 8: key 2: x2 holds 00000009, last written 00000007
  error[registers.architectural] registers cycle 3 time 8: key 2: x2 retired as 00000007, storage holds 00000009
  [1]

--at prints the storage as of the last change at or before that cycle (changes were in cycles 0, 2 and 3):

  $ coralview registers --platform reg-core.json --at 1 registers.vcd | grep -A1 'storage at cycle'
  storage at cycle 0:
    x1   00000000  x2   00000000  x3   00000000  f0   00000000
  $ coralview registers --platform reg-core.json --at 2 registers.vcd | grep -A1 'storage at cycle'
  storage at cycle 2:
    x1   0000002a  x2   00000000  x3   00000000  f0   00000000
  $ coralview registers --platform reg-core.json --at 100 registers.vcd | grep -A1 'storage at cycle'
  storage at cycle 3:
    x1   0000002a  x2   00000007  x3   00000000  f0   00000000

The scoreboards are as wide as the description says, not 32 bits: the same run on a core whose
scoreboards have one bit per register (x0-x3, f0), described as such:

  $ sed -e '/"first": 1,/s/"scoreboard_entries": 32/"scoreboard_entries": 4/' -e '/"first": 0,/s/"scoreboard_entries": 32/"scoreboard_entries": 1/' reg-core.json > narrow-core.json
  $ coralview registers --platform narrow-core.json narrow.vcd
  platform reg-core
  root TOP.core: 7 cycles
  registers.storage                 2 comparisons, 0 failures
  registers.scoreboard             10 comparisons, 0 failures
  registers.flushed                10 comparisons, 0 failures
  registers.architectural           2 comparisons, 0 failures
  1 pipeline flushes
  storage at the end:
    x1   0000002a  x2   00000007  x3   00000000  f0   00000000

A description that says 32 does not match that trace, and one with fewer entries than registers is not a
description:

  $ coralview registers --platform reg-core.json narrow.vcd
  platform reg-core does not match the trace (model registers):
    width   scoreboard 4, expected 32: write pending
  [3]
  $ sed '/"first": 1,/s/"scoreboard_entries": 32/"scoreboard_entries": 3/' reg-core.json > small-core.json
  $ coralview registers --platform small-core.json registers.vcd 2>&1 | head -3
  register file: 3 scoreboard entries for registers up to 3
  File "small-core.json": in member x_registers of
  File "small-core.json", lines 9-22, characters 12-6: blocks object
