A vfmacc.vf (8 elements, 16 operations), a vle32.v, a vadd.vv from element 2 of 6 (4), a vmv.v.i
(a move), then, after an idle gap, the vfmacc.vf again with vl 4 (8) and a uop at a PC the scalar core
never dispatched. A second uop of the first vfmacc.vf, and a uop not taken, are not counted:

  $ coralview ops --platform ops-core.json --gap 3 --peak-window 4 --profile 5 ops.vcd
  root TOP.core: 12 cycles, 6 vector instructions dispatched (1 not decoded)
    unit   instructions     elements          ops
    alu               3           14            4
    fma               2           12           24
    lsu               1            8            0
  28 ops (24 floating point) in 2 bursts over 4 cycles (33.3% of the trace)
  ops/cycle: 2.333 over the trace, 7.000 in bursts, peak 5.000 over 4 cycles to cycle 3
  bursts:
         first       last   cycles   instrs        ops ops/cycle
             1          3        3        2         20     6.667
             9          9        1        1          8     8.000
  operations by instruction:
        pc  count        ops   elements  instruction
  00000100      2         24         12  vfmacc.vf
  00000108      1          4          4  vadd.vv
  00000104      1          0          8  vle32.v
  0000010c      1          0          8  vmv.v.i
  00000200      1          0          2  ? alu

As JSON lines:

  $ coralview ops --platform ops-core.json --gap 3 --peak-window 4 --format jsonl ops.vcd | jq -c 'select(.type != "coralview")'
  {"type":"ops.op","cycle":1,"pc":256,"unit":"fma","mnemonic":"vfmacc.vf","sew":32,"lmul":"1","vl":8,"vstart":0,"kind":"fma","float":true,"elements":8,"ops":16}
  {"type":"ops.op","cycle":2,"pc":260,"unit":"lsu","mnemonic":"vle32.v","sew":32,"lmul":"1","vl":8,"vstart":0,"kind":"memory","float":false,"elements":8,"ops":0}
  {"type":"ops.op","cycle":3,"pc":264,"unit":"alu","mnemonic":"vadd.vv","sew":32,"lmul":"1","vl":6,"vstart":2,"kind":"arith","float":false,"elements":4,"ops":4}
  {"type":"ops.op","cycle":5,"pc":268,"unit":"alu","mnemonic":"vmv.v.i","sew":32,"lmul":"1","vl":8,"vstart":0,"kind":"move","float":false,"elements":8,"ops":0}
  {"type":"ops.burst","first":1,"last":3,"instructions":2,"ops":20,"flops":16}
  {"type":"ops.op","cycle":9,"pc":256,"unit":"fma","mnemonic":"vfmacc.vf","sew":32,"lmul":"1","vl":4,"vstart":0,"kind":"fma","float":true,"elements":4,"ops":8}
  {"type":"ops.op","cycle":10,"pc":512,"unit":"alu","sew":32,"lmul":"1","vl":2,"vstart":0,"kind":"other","float":false,"elements":2,"ops":0}
  {"type":"ops.burst","first":9,"last":9,"instructions":1,"ops":8,"flops":8}
  {"type":"ops.summary","cycles":12,"instructions":6,"undecoded":1,"ops":28,"flops":24,"bursts":2,"busy":4,"peak":{"window":4,"ops":20,"last":3},"units":[{"unit":"alu","instructions":3,"elements":14,"ops":4},{"unit":"fma","instructions":2,"elements":12,"ops":24},{"unit":"lsu","instructions":1,"elements":8,"ops":0}]}

As a Chrome trace for ui.perfetto.dev: the bursts, each instruction on its unit's track, and the
operations of each 64-cycle window as a counter:

  $ coralview run --platform ops-core.json --model ops --perfetto ops.json ops.vcd
  $ jq -c '.traceEvents[] | select(.ph == "X") | [.tid, .name, .ts, .dur]' ops.json
  [1,"28 ops",1,9]
  [2,"vfmacc.vf",1,1]
  [3,"vle32.v",2,1]
  [4,"vadd.vv",3,1]
  [4,"vmv.v.i",5,1]
  [2,"vfmacc.vf",9,1]
  [4,"?",10,1]
  $ jq -c '.traceEvents[] | select(.ph == "C") | [.name, .ts, .args]' ops.json
  ["ops per 64 cycles",0,{"value":28}]
  ["ops per 64 cycles",64,{"value":0}]
