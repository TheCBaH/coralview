A VCD on standard input, with "-" as the trace, gives what the file gives:

  $ t=../signals.t
  $ args="--platform $t/sig.json"
  $ sigs="TOP.sim/core/count TOP.sim/core/data"
  $ coralview signals $args $t/sig.vcd $sigs > file.txt
  $ cat $t/sig.vcd | coralview signals $args - $sigs | cmp - file.txt

whatever the size of the writes, and a writer that stalls:

  $ for n in 1 7 4096; do dd if=$t/sig.vcd bs=$n 2>/dev/null | coralview signals $args - $sigs | cmp - file.txt; done
  $ (head -c 200 $t/sig.vcd; sleep 1; tail -c +201 $t/sig.vcd) | coralview signals $args - $sigs | cmp - file.txt

If the producer fails after a valid prefix, the consumer sees an ordinary end of
input and summarises it; the pipeline status is the only sign of the failure:

  $ cat > pipeline.sh <<'SH'
  > set -o pipefail
  > (head -n 17 "$1"; exit 1) | coralview signals --platform "$2" - TOP.sim/core/count
  > echo "pipeline status $?"
  > SH
  $ bash pipeline.sh $t/sig.vcd $t/sig.json
  # sampled after_falling on io_aclk at TOP.sim.core
  pipeline status 1

A cut at a record boundary is a valid prefix:

  $ head -n 17 $t/sig.vcd | coralview signals $args - $sigs

A cut inside a record, a header without $enddefinitions, and an open $dumpvars
block are errors:

  $ head -n 17 $t/sig.vcd | head -c -1 | coralview signals $args - $sigs
  [1]
  $ head -n 8 $t/sig.vcd | coralview signals $args - $sigs
  [1]
  $ head -n 14 $t/sig.vcd | coralview signals $args - $sigs
  [1]

FST is not read from standard input:

  $ cat ../memory.t/memory.fst | coralview signals $args - $sigs
  [1]
