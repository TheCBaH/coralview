The selected trace holds only the declarations of the manifest, and the changes of those:

  $ t=..
  $ sel=../../tools/select_trace.exe
  $ coralview plan --platform $t/platform.t/test-core.json --model commits --catalog $t/platform.t/core.vcd -o out > /dev/null
  $ $sel out/select $t/platform.t/core.vcd | head -n 12
  $timescale 1ps $end
  $scope module TOP $end
  $scope module core $end
  $var wire 1 ! io_aclk $end
  $var wire 1 " io_debug_dispatch_0_instFire $end
  $var wire 32 # io_debug_dispatch_0_instAddr $end
  $var wire 32 $ io_debug_dispatch_0_instInst $end
  $var wire 1 % io_debug_rb_inst_0_valid $end
  $var wire 32 & io_debug_rb_inst_0_bits_pc $end
  $var wire 7 ' io_debug_rb_inst_0_bits_idx $end
  $var wire 1 ( io_debug_rb_inst_0_bits_trap $end
  $var wire 1 ) io_debug_regfile_writeData_0_valid $end
  $ $sel out/select $t/platform.t/core.vcd | grep -c '^\$var'
  11

A name no declaration has is an error, as for the producer:

  $ printf 'hwfrp-verilator-select 1\nselect TOP core nope\n' > bad.select
  $ $sel bad.select $t/platform.t/core.vcd
  select-trace: no declaration named "TOP core nope"
  [1]

For each model on its fixture, the analysis on the selected trace, checked against the plan,
gives what the full trace gives:

  $ while read m dir json vcd; do
  >   p=$t/$dir/$json; v=$t/$dir/$vcd
  >   coralview plan --platform $p --model $m --catalog $v -o $m.d > /dev/null || echo "$m: plan failed"
  >   $sel $m.d/select $v > $m.sel.vcd || echo "$m: select failed"
  >   coralview $m --platform $p $v > $m.full 2>&1; echo "$m: $?" > $m.full.status
  >   coralview $m --platform $p --plan $m.d/plan $m.sel.vcd > $m.part 2>&1; echo "$m: $?" > $m.part.status
  >   cmp $m.full $m.part && cmp $m.full.status $m.part.status && echo "$m: same, $(cat $m.part.status)"
  > done <<EOF2
  > commits platform.t test-core.json core.vcd
  > stalls stalls.t stall-core.json stalls.vcd
  > memory memory.t mem-core.json memory.vcd
  > axi axi.t axi-core.json axi.vcd
  > registers registers.t reg-core.json registers.vcd
  > tiles tiles.t tile-core.json tiles.vcd
  > ops ops.t ops-core.json ops.vcd
  > vectors vectors.t vector-core.json vectors.vcd
  > traps traps.t trap-core.json traps.vcd
  > dma dma.t dma-sub.json dma.vcd
  > EOF2
  commits: same, commits: 0
  stalls: same, stalls: 0
  memory: same, memory: 0
  axi: same, axi: 0
  registers: same, registers: 0
  tiles: same, tiles: 0
  ops: same, ops: 0
  vectors: same, vectors: 0
  traps: same, traps: 0
  dma: same, dma: 0
