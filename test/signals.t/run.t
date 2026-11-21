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

With --format jsonl, one record per value between a header and a summary:

  $ coralview signals --platform sig.json --changes --format jsonl --to-cycle 2 sig.vcd TOP.sim/core/data
  {"type":"coralview","schema_version":3,"model":"signals","platform":"sig-core","trace":"sig.vcd"}
  {"type":"signals.sample","phase":"after_falling","cycle":0,"time":2,"path":"TOP.sim/core/data","width":8,"value":"0bxxxxxxxx"}
  {"type":"signals.sample","phase":"after_falling","cycle":1,"time":4,"path":"TOP.sim/core/data","width":8,"value":"0b1010xxxx"}
  {"type":"signals.sample","phase":"after_falling","cycle":2,"time":6,"path":"TOP.sim/core/data","width":8,"value":"0xa5"}
  {"type":"signals.summary","samples":3}

--json is the same:

  $ coralview signals --platform sig.json --changes --format jsonl --to-cycle 2 sig.vcd TOP.sim/core/data > typed.json
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

A value that is not a bit vector, here a real, does not stop --raw: the signal reads as unknown, and the
signal is named once on the standard error:

  $ cat > real.vcd <<'VCD'
  > $timescale 1ps $end
  > $scope module TOP $end
  > $var real 64 ! temp $end
  > $var wire 4 " count $end
  > $upscope $end
  > $enddefinitions $end
  > #0
  > r1.5 !
  > b1 "
  > #1
  > r2.5 !
  > b10 "
  > VCD
  $ coralview signals --raw real.vcd TOP/temp TOP/count 2> err.txt
         -          0   64 TOP/temp 0bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
         -          0    4 TOP/count 0x1
         -          1   64 TOP/temp 0bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
         -          1    4 TOP/count 0x2
  $ cat err.txt
  TOP/temp: not a bit vector: 1.5; read as unknown

The sampled form reads such a value as unknown too, and names the signal once, as requested:

  $ sed 's/^b10100101 #/r1.5 #/' sig.vcd > badval.vcd
  $ coralview signals --platform sig.json --from-cycle 2 --to-cycle 3 badval.vcd TOP.sim/core/data 2> err.txt
  # sampled after_falling on io_aclk at TOP.sim.core
         2          6    8 TOP.sim/core/data 0bxxxxxxxx
         3          8    8 TOP.sim/core/data 0bxxxxxxxx
  $ cat err.txt
  TOP.sim/core/data: not a bit vector: 1.5; read as unknown

A VCD file is read as strictly as standard input is. One without its final newline, or with a
$dumpvars that is still open, is a cut file, and the error names the file:

  $ head -c -1 sig.vcd > nonl.vcd
  $ coralview signals --platform sig.json nonl.vcd TOP.sim/core/count > /dev/null
  coralview: trace read failed (incomplete): input does not end with a newline at nonl.vcd line 41 col 6
  [3]
  $ sed '/^bx #$/q' sig.vcd > open.vcd
  $ coralview signals --platform sig.json open.vcd TOP.sim/core/count > /dev/null
  coralview: trace read failed (incomplete): unterminated dump block at end of input at open.vcd line 15 col 0
  [3]

From an FST file, --from-time starts at the block that holds the time instead of at the beginning. seek.fst
is seek.vcd through tools/vcd2fst.sh, with a block ended after #3 and after #7. Here top/a repeats its value
at the start of the second and third blocks, and top/d is first assigned in the third, with the value its
frame holds. The results are those of the whole file; a VCD file is scanned from the start, so a single
signal prints the same from both:

  $ coralview signals --raw --changes --from-time 5 seek.fst top/a top/b top/d
         -          5    8 top/b 0x04
         -          6    8 top/a 0x07
         -          9    8 top/d 0bxxxxxxxx
         -         10    8 top/d 0xaa
         -         11    8 top/a 0x01
  $ coralview signals --raw --changes --from-time 9 seek.fst top/d
         -          9    8 top/d 0bxxxxxxxx
         -         10    8 top/d 0xaa
  $ for t in 0 3 4 5 7 8 9 10 12; do
  >   for s in a b d; do
  >     for c in "" --changes; do
  >       coralview signals --raw $c --from-time $t seek.fst top/$s > fst.out
  >       coralview signals --raw $c --from-time $t seek.vcd top/$s | cmp - fst.out || echo "$t $s $c"
  >     done
  >   done
  > done
