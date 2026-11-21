coralview can run the producer of a stream itself, with its descriptor 3 as the stream, and
say in its output how the producer ended:

  $ t=../signals.t
  $ args="--platform $t/sig.json"
  $ coralview signals $args $t/sig.vcd TOP.sim/core/count > file.txt
  $ coralview signals $args --exec "cat $t/sig.vcd >&3" - TOP.sim/core/count > complete.txt
  $ cat complete.txt
  # sampled after_falling on io_aclk at TOP.sim.core
         0          2    4 TOP.sim/core/count 0x1
         1          4    4 TOP.sim/core/count 0x2
         2          6    4 TOP.sim/core/count 0x3
         3          8    4 TOP.sim/core/count 0x3
         4         10    4 TOP.sim/core/count 0x4
  # producer: complete, exited with status 0
  $ sed '$d' complete.txt | cmp - file.txt

A producer that fails after a valid prefix: the results describe what was seen, the status says
why they may be short, and the exit status is 4:

  $ coralview signals $args --exec "head -n 17 $t/sig.vcd >&3; exit 3" - TOP.sim/core/count
  # sampled after_falling on io_aclk at TOP.sim.core
  # producer: failed, exited with status 3; the trace may be incomplete
  [4]

A consumer that stops reading first ends the producer with the closed pipe, which is not a failure:

  $ coralview signals $args --to-cycle 1 --exec "(cat $t/sig.vcd; while :; do echo '#99'; done) >&3" - TOP.sim/core/count
  # sampled after_falling on io_aclk at TOP.sim.core
         0          2    4 TOP.sim/core/count 0x1
         1          4    4 TOP.sim/core/count 0x2
  # producer: cancelled by the consumer, exited with status 141

In JSON lines the status is a last record:

  $ coralview signals $args --format jsonl --exec "cat $t/sig.vcd >&3" - TOP.sim/core/count | tail -n 2
  {"type":"signals.summary","samples":5}
  {"type":"producer","command":"cat ../signals.t/sig.vcd >&3","outcome":"complete","status":0}
  $ coralview signals $args --format jsonl --exec "head -n 17 $t/sig.vcd >&3; exit 3" - TOP.sim/core/count | tail -n 1
  {"type":"producer","command":"head -n 17 ../signals.t/sig.vcd >&3; exit 3","outcome":"failed","status":3}

A stream cut inside a record is an error of the consumer; the producer finished:

  $ coralview signals $args --exec "head -n 17 $t/sig.vcd | head -c -1 >&3" - TOP.sim/core/count
  # sampled after_falling on io_aclk at TOP.sim.core
  coralview: trace read failed (incomplete): input does not end with a newline at <channel> line 17 col 2
  # producer: complete, exited with status 0
  [3]

The producer makes the trace, so no other trace is named:

  $ coralview signals $args --exec "cat $t/sig.vcd >&3" $t/sig.vcd TOP.sim/core/count
  --exec produces the trace: give - as the trace
  [2]

The producer starts once the whole command line is evaluated, so a command that fails on its
platform never runs it, and no status is written for it:

  $ coralview signals --platform nosuch.json --exec "touch started; cat $t/sig.vcd >&3" - TOP.sim/core/count
  no platform nosuch.json: give a configuration (coralview platforms) or a JSON file
  [2]
  $ test -e started
  [1]
  $ coralview signals --platform nosuch.json --raw --exec "cat $t/sig.vcd >&3" - TOP.sim/core/count | tail -n 2
         -         10    4 TOP.sim/core/count 0x4
  # producer: complete, exited with status 0

Descriptor 3 of the producer is the write end of the stream, a pipe, whatever the caller had there;
its other descriptors are the caller's. The caller's descriptor 3 is not written to:

  $ coralview signals $args --exec "test -p /dev/fd/3 && echo pipe >&2; echo kept >&4; cat $t/sig.vcd >&3" - TOP.sim/core/count 3>caller3.txt 4>caller4.txt > fds.txt
  pipe
  $ tail -n 1 fds.txt
  # producer: complete, exited with status 0
  $ test -s caller3.txt
  [1]
  $ cat caller4.txt
  kept

The same when the pipe is allocated descriptor 3 itself, with the standard input closed, and the
producer's standard input is the caller's:

  $ coralview signals $args --exec "test -p /dev/fd/3 && echo pipe >&2; cat $t/sig.vcd >&3" - TOP.sim/core/count 0<&- | tail -n 2
  pipe
         4         10    4 TOP.sim/core/count 0x4
  # producer: complete, exited with status 0
  $ echo caller | coralview signals $args --exec "read line; echo \$line >&2; cat $t/sig.vcd >&3" - TOP.sim/core/count | tail -n 1
  caller
  # producer: complete, exited with status 0
