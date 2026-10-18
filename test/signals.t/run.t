A trace whose top scope name has a dot. Each cycle, sampled after the
falling edge; unknown bits print as x:

  $ coralview signals --platform sig.json sig.vcd TOP.sim/core/count TOP.sim/core/data
  # sampled after_falling on io_aclk at TOP.sim.core
         0          2    4 TOP.sim/core/count 0x1
         0          2    8 TOP.sim/core/data 0bxxxxxxxx
         1          4    4 TOP.sim/core/count 0x2
         1          4    8 TOP.sim/core/data 0b1010xxxx
         2          6    4 TOP.sim/core/count 0x3
         2          6    8 TOP.sim/core/data 0xa5
         3          8    4 TOP.sim/core/count 0x3
         3          8    8 TOP.sim/core/data 0xa5
         4         10    4 TOP.sim/core/count 0x4
         4         10    8 TOP.sim/core/data 0xa5

Only the changes, in a window; the window's first cycle shows every value:

  $ coralview signals --platform sig.json --changes --from-cycle 1 --to-cycle 3 sig.vcd TOP.sim/core/count TOP.sim/core/data
  # sampled after_falling on io_aclk at TOP.sim.core
         1          4    4 TOP.sim/core/count 0x2
         1          4    8 TOP.sim/core/data 0b1010xxxx
         2          6    4 TOP.sim/core/count 0x3
         2          6    8 TOP.sim/core/data 0xa5

As JSON lines:

  $ coralview signals --platform sig.json --changes --json --to-cycle 2 sig.vcd TOP.sim/core/data
  {"phase":"after_falling","cycle":0,"time":2,"path":"TOP.sim/core/data","width":8,"value":"0bxxxxxxxx"}
  {"phase":"after_falling","cycle":1,"time":4,"path":"TOP.sim/core/data","width":8,"value":"0b1010xxxx"}
  {"phase":"after_falling","cycle":2,"time":6,"path":"TOP.sim/core/data","width":8,"value":"0xa5"}

With --format jsonl the same records carry a type, between a header and a summary:

  $ coralview signals --platform sig.json --changes --format jsonl --to-cycle 2 sig.vcd TOP.sim/core/data
  {"type":"coralview","schema_version":1,"model":"signals","platform":"sig-core","trace":"sig.vcd"}
  {"type":"signals.sample","phase":"after_falling","cycle":0,"time":2,"path":"TOP.sim/core/data","width":8,"value":"0bxxxxxxxx"}
  {"type":"signals.sample","phase":"after_falling","cycle":1,"time":4,"path":"TOP.sim/core/data","width":8,"value":"0b1010xxxx"}
  {"type":"signals.sample","phase":"after_falling","cycle":2,"time":6,"path":"TOP.sim/core/data","width":8,"value":"0xa5"}
  {"type":"signals.summary","samples":3}
  $ coralview signals --platform sig.json --changes --format jsonl --to-cycle 2 sig.vcd TOP.sim/core/data | jq -c 'select(.type == "signals.sample") | del(.type)' > typed.json
  $ coralview signals --platform sig.json --changes --json --to-cycle 2 sig.vcd TOP.sim/core/data | cmp - typed.json

The raw value changes, by timestamp, with no clock:

  $ coralview signals --raw --from-time 4 --to-time 6 sig.vcd TOP.sim/core/count TOP.sim/core/data
         -          4    4 TOP.sim/core/count 0x2
         -          4    8 TOP.sim/core/data 0b1010xxxx
         -          6    4 TOP.sim/core/count 0x3
         -          6    8 TOP.sim/core/data 0xa5

A path the trace does not have is an error, in both modes. Splitting the
dotted scope name is such a path:

  $ coralview signals --platform sig.json sig.vcd TOP.sim/core/nope
  no signal TOP.sim/core/nope in the trace
  [3]
  $ coralview signals --raw sig.vcd TOP/sim/core/count
  no signal TOP/sim/core/count in the trace
  [3]

Cycles and timestamps are not interchangeable:

  $ coralview signals --raw --from-cycle 2 sig.vcd TOP.sim/core/count
  --raw selects timestamps: use --from-time and --to-time
  [2]
  $ coralview signals --platform sig.json --to-time 4 sig.vcd TOP.sim/core/count
  --from-time and --to-time select raw timestamps: add --raw
  [2]
