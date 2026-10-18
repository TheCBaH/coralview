Two dispatch lanes. In cycle 0 lane 0 dispatches an addi while lane 1 holds an add that reads x10,
which the scoreboard keeps busy until cycle 3. The add moves to lane 0 and waits there on the RAW
hazard for two more cycles, with lane 1 behind it. Then both lanes run dry, and lane 0's next
instruction meets a halt:

  $ coralview stalls --platform stall-core.json --profile 3 stalls.vcd
  root TOP.core: 6 cycles
  reason           lane0   lane1
  dispatched           2       0
  empty                1       3
  behind               0       2
  halted               1       0
  raw                  2       1
  lane 0 blocked, by instruction:
        pc cycles reason         instruction
  00000104      2 raw            add x11, x10, x10
  00000108      1 halted         add x12, x10, x11

As JSON lines, one span per run of a lane with the same reason and instruction; those still running
at the end are open:

  $ coralview stalls --platform stall-core.json --format jsonl stalls.vcd | jq -c 'select(.type == "stalls.span") | [.lane, .reason, .pc, .span.start, .span.stop]'
  [0,"dispatched",256,0,0]
  [1,"raw",260,0,0]
  [0,"raw",260,1,2]
  [1,"behind",264,1,2]
  [0,"dispatched",260,3,3]
  [0,"empty",260,4,4]
  [0,"halted",264,5,null]
  [1,"empty",264,3,null]
