Two instructions write x1 and x2: each is announced when it dispatches (the marks), written back,
stored in the register file one sample later and retired. The pipeline flushes in cycle 4. The
register file, the scoreboards and the retirements agree:

  $ coralview registers --platform reg-core.json registers.vcd
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
  {"type":"coralview","schema_version":1,"model":"registers","platform":"reg-core","trace":"registers.vcd"}
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
