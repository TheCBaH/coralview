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

A plan made for other models says so, instead of listing the signals of the model it lacks:

  $ coralview axi --platform $t/axi.t/axi-core.json --plan out/plan $t/axi.t/axi.vcd
  the plan out/plan was made without --model axi (it has commits)
  [3]
  $ coralview run --platform $t/axi.t/axi-core.json --model commits --model axi --plan out/plan $t/axi.t/axi.vcd
  the plan out/plan was made without --model axi (it has commits)
  [3]

Two declarations of one id are one signal: its changes are written once, for both names, and a 64-bit
vector with its top bit set is written in full. alias.fst is alias.vcd through tools/vcd2fst.sh (libfst's
writer), where the second name is an alias of the first handle:

  $ $sel alias.select alias.vcd | sed -n '4,$p'
  $var wire 1 ! clk $end
  $var wire 64 " wide $end
  $var wire 8 # data $end
  $scope module view $end
  $var wire 8 # data_copy $end
  $upscope $end
  $upscope $end
  $upscope $end
  $enddefinitions $end
  #0
  0!
  b0 "
  b0 #
  #1
  1!
  b1000000000000000000000000000000000000000000000000000000000000001 "
  b10100101 #
  #2
  0!
  b1111111111111111111111111111111111111111111111111111111111111111 "
  b1 #
  #3
  1!
  b101 "
  $ $sel alias.select alias.fst | sed -n '4,$p'
  $var wire 1 ! clk $end
  $var wire 64 " wide $end
  $var wire 8 # data $end
  $scope module view $end
  $var wire 8 # data_copy $end
  $upscope $end
  $upscope $end
  $upscope $end
  $enddefinitions $end
  #0
  b0 #
  b0 "
  0!
  #1
  1!
  b1000000000000000000000000000000000000000000000000000000000000001 "
  b10100101 #
  #2
  b1 #
  b1111111111111111111111111111111111111111111111111111111111111111 "
  0!
  #3
  1!
  b101 "

A VCD that is cut, as its consumers see it, is an error and not a short trace: this one lacks its last
newline, this one stops inside $dumpvars:

  $ printf '%s' "$(cat alias.vcd)" > nonl.vcd
  $ $sel alias.select nonl.vcd > /dev/null
  select-trace: input does not end with a newline at nonl.vcd line 29 col 6
  [1]
  $ sed -n '1,/^b0 #$/p' alias.vcd > open.vcd
  $ $sel alias.select open.vcd > /dev/null
  select-trace: unterminated dump block at end of input at open.vcd line 18 col 0
  [1]
