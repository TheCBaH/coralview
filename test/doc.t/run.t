The JSONL schema in doc/coralnpu.md is what the analyses write on the test fixtures:

  $ t=..
  $ coralview commits --platform $t/platform.t/test-core.json --format jsonl $t/platform.t/core.vcd > commits.jsonl
  $ coralview stalls --platform $t/stalls.t/stall-core.json --format jsonl $t/stalls.t/stalls.vcd > stalls.jsonl
  $ coralview memory --platform $t/memory.t/mem-core.json --format jsonl $t/memory.t/memory.vcd > memory.jsonl
  $ coralview axi --platform $t/axi.t/axi-core.json --format jsonl $t/axi.t/axi.vcd > axi.jsonl
  $ coralview dma --platform $t/dma.t/dma-sub.json --format jsonl $t/dma.t/dma.vcd > dma.jsonl
  $ coralview tiles --platform $t/tiles.t/tile-core.json --format jsonl $t/tiles.t/tiles.vcd > tiles.jsonl
  $ coralview ops --platform $t/ops.t/ops-core.json --format jsonl $t/ops.t/ops.vcd > ops.jsonl
  $ coralview vectors --platform $t/vectors.t/vector-core.json --format jsonl $t/vectors.t/bad.vcd > vectors.jsonl
  [1]
  $ coralview traps --platform $t/traps.t/trap-core.json --format jsonl $t/traps.t/traps.vcd > traps.jsonl
  $ coralview signals --platform $t/signals.t/sig.json --format jsonl $t/signals.t/sig.vcd TOP.sim/core/data > signals.jsonl
  $ coralview check --platform $t/platform.t/test-core.json --format jsonl $t/platform.t/core.vcd > check.jsonl
  $ $t/../tools/jsonl-schema.sh *.jsonl > schema.txt
  $ sed -n '/^<!-- schema -->$/,/^<!-- end schema -->$/p' $t/../doc/coralnpu.md | sed '1,2d;$d' | sed '$d' | diff - schema.txt
