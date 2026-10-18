A load's external read waits a cycle for the address channel; an instruction fetch from external RAM
overlaps it on ID 1 and is answered first. Two instances of a store queue in the LSU and both retire
before the second makes its request; the queue pins each write to its own instance. The first store's
data is accepted before its address. A write response arrives for an ID with nothing outstanding, and
the last read is not the address the LSU asked for and is never answered:

  $ coralview axi --platform axi-core.json --profile 3 axi.vcd
     start   accept     done dir  id source addr                 bytes beats B/cycle out  origin
         1        3        6 R     0 lsu    20000000                16  1x16    2.67   1  pc 00000100 lw x10, 0(x10) (dispatched 0, op 1, retired 7)
         3        4        5 R     1 fetch  20001000                16  1x16    5.33   2  request 20001004
         8        9       11 W     0 lsu    20000010                 4  1x16    1.00   1  pc 00000104 sw x11, 16(x10) (dispatched 7, op 8, retired 9)
        13       13       15 W     0 lsu    20000014                 4  1x16    1.33   1  pc 00000104 sw x11, 16(x10) (dispatched 8, op 12, retired 10)
        17       18        - R     0 lsu    20000030                 0  1x16       -   1  pc 00000108 lw x10, 32(x10) (dispatched 16, op 17, retired -); DISAGREES: request R 20000020
        16 unmatched W id 3: write response with no outstanding write
  root TOP.core: reads 3 (32 bytes), writes 2 (8 bytes) in 21 cycles, unmatched 1
    latency, address accepted to done, min/mean/max: reads 1/2.0/3, writes 2/2.0/2 cycles; 1 not done when the trace ends
    throughput 2.000 bytes/cycle over cycles 1-20, 3.077 while a transaction is outstanding (13 cycles)
    outstanding at once: max 2 (reads 2, writes 1); cycles by count: 0:5 1:11 2:2
    source lsu (id 0): transactions 4, bytes 24, pinned to a request 4, to an instruction instance 4, DISAGREEING 1
    source fetch (id 1): transactions 1, bytes 16, pinned to a request 1, to an instruction instance 0
  external traffic by instruction:
        pc  count   bytes  cycles  instruction
  00000100      1      16       6  lw x10, 0(x10)
  00000104      2       8       7  sw x11, 16(x10)
  00000108      1       0       0  lw x10, 32(x10)

Without the LSU's PC the description does not match the trace:

  $ sed 's/"io_ebus_dbus_pc"/"io_ebus_dbus_pc_q"/' axi-core.json > renamed.json
  $ coralview axi --platform renamed.json axi.vcd
  platform axi-core does not match the trace (model axi):
    missing io_ebus_dbus_pc_q
  [3]

The same transactions as JSON lines: a header, the events in acceptance order with the instance each
is pinned to, the unmatched ones as they came, and the summary. The window and the limit select
events; the summary covers the whole trace:

  $ coralview axi --platform axi-core.json --format jsonl --limit 2 axi.vcd
  {"type":"coralview","schema_version":1,"model":"axi","platform":"axi-core","trace":"axi.vcd"}
  {"type":"axi.transaction","transaction":{"id":0,"write":false,"address":536870912,"bytes":16,"beats":1,"requested":2,"accepted":3,"first_data":6,"completed":6,"status":0,"outstanding":1},"source":"lsu","origin":{"issued":1,"request":536870912,"write":false,"agrees":true,"instance":{"pc":256,"word":337155,"dispatched":0,"issued":1,"retired":7}},"burst":1,"beat_bytes":16}
  {"type":"axi.transaction","transaction":{"id":1,"write":false,"address":536875008,"bytes":16,"beats":1,"requested":4,"accepted":4,"first_data":5,"completed":5,"status":0,"outstanding":2},"source":"fetch","origin":{"issued":3,"request":536875012,"agrees":true},"burst":1,"beat_bytes":16}
  {"type":"axi.summary","cycles":21,"reads":3,"read_bytes":32,"writes":2,"write_bytes":8,"unmatched":1,"read_latency":{"n":2,"min":1,"max":3,"sum":4},"write_latency":{"n":2,"min":2,"max":2,"sum":4},"incomplete":1,"first":1,"last":20,"occupancy":[5,11,2],"max_reads":2,"max_writes":1,"sources":[{"id":0,"source":"lsu","transactions":4,"bytes":24,"pinned":4,"instances":4,"disagreeing":1},{"id":1,"source":"fetch","transactions":1,"bytes":16,"pinned":1,"instances":0,"disagreeing":0}],"resyncs":0,"words":[{"pc":256,"word":337155},{"pc":260,"word":11872291},{"pc":264,"word":33891587}]}
  $ coralview axi --platform axi-core.json --format jsonl axi.vcd | jq -c 'select(.type == "axi.transaction") | [.transaction.accepted, .transaction.address, .origin.instance.pc, .origin.instance.retired]'
  [3,536870912,256,7]
  [4,536875008,null,null]
  [9,536870928,260,9]
  [13,536870932,260,10]
  [18,536870960,264,null]
  $ coralview axi --platform axi-core.json --format jsonl axi.vcd | jq -r .type | uniq -c
        1 coralview
        4 axi.transaction
        1 axi.unmatched
        1 axi.transaction
        1 axi.summary

--output writes what the standard output would get:

  $ coralview axi --platform axi-core.json --profile 3 --output axi.txt axi.vcd
  $ coralview axi --platform axi-core.json --profile 3 axi.vcd | cmp - axi.txt
  $ coralview axi --platform axi-core.json --format jsonl -o axi.jsonl axi.vcd
  $ coralview axi --platform axi-core.json --format jsonl axi.vcd | cmp - axi.jsonl
