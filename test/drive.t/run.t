coralview can run the producer of a stream itself, with its descriptor 3 as the stream, and
say in its output how the producer ended:

  $ t=../signals.t
  $ args="--platform $t/sig.json"
  $ coralview signals $args $t/sig.vcd TOP.sim/core/count > file.txt
  $ coralview signals $args --exec "cat $t/sig.vcd >&3" - TOP.sim/core/count > complete.txt
  $ cat complete.txt
  $ sed '$d' complete.txt | cmp - file.txt

A producer that fails after a valid prefix: the results describe what was seen, the status says
why they may be short, and the exit status is 4:

  $ coralview signals $args --exec "head -n 17 $t/sig.vcd >&3; exit 3" - TOP.sim/core/count
  [4]

A consumer that stops reading first ends the producer with the closed pipe, which is not a failure:

  $ coralview signals $args --to-cycle 1 --exec "(cat $t/sig.vcd; while :; do echo '#99'; done) >&3" - TOP.sim/core/count

In JSON lines the status is a last record:

  $ coralview signals $args --format jsonl --exec "cat $t/sig.vcd >&3" - TOP.sim/core/count | tail -n 2
  $ coralview signals $args --format jsonl --exec "head -n 17 $t/sig.vcd >&3; exit 3" - TOP.sim/core/count | tail -n 1
  [4]

A stream cut inside a record is an error of the consumer; the producer finished:

  $ coralview signals $args --exec "head -n 17 $t/sig.vcd | head -c -1 >&3" - TOP.sim/core/count
  [1]

The producer makes the trace, so no other trace is named:

  $ coralview signals $args --exec "cat $t/sig.vcd >&3" $t/sig.vcd TOP.sim/core/count
  [2]
