Requests on the LSU's TileLink-UL port: a write and a read to the TCM, whose data comes the cycle after
the request, the same to an external address with slower responses, then two faults, the first with a
request from its PC before it, and a last read whose data is unknown. A read is reported with its
response, but at the cycle of its request, so the second external read, answered after the faults, is
listed before them:

  $ coralview memory --platform mem-core.json memory.vcd
  platform mem-core
         0 W pc 00000100 addr 00010004 4 bytes deadbeef
         1 R pc 00000104 addr 00010008 4 bytes 11223344
         3 W pc 00000108 addr 20000000 4 bytes cafef00d
         4 R pc 0000010c addr 20000010 4 bytes 55667788
         5 fault R pc 0000010c addr 30000000, requested at 4, addr 20000010
         6 fault W pc 00000110 addr 00000040, no request seen
         7 R pc 00000114 addr 20000020 4 bytes 00000000
  root TOP.core: 3 read and 2 write requests from 5 PCs, 2 faults

A window counts its own requests:

  $ coralview memory --platform mem-core.json --from-cycle 3 --to-cycle 5 memory.vcd
  platform mem-core
         3 W pc 00000108 addr 20000000 4 bytes cafef00d
         4 R pc 0000010c addr 20000010 4 bytes 55667788
         5 fault R pc 0000010c addr 30000000, requested at 4, addr 20000010
  root TOP.core: 3 read and 2 write requests from 5 PCs, 2 faults
  window [3, 5]: 1 read and 1 write requests from 2 PCs, 1 faults

As JSON lines, with each request's byte lanes and its line of data, in the order they were reported (a read
after its response, so after a fault that came sooner); the unknown data is a diagnostic line:

  $ coralview memory --platform mem-core.json --format jsonl memory.vcd
  {"type":"coralview","schema_version":3,"model":"memory","platform":"mem-core","trace":"memory.vcd"}
  {"type":"memory.access","cycle":0,"pc":256,"access":{"address":65540,"bytes":4,"write":true},"lanes":[4,5,6,7],"data":"0000000000000000deadbeef00000000"}
  {"type":"memory.access","cycle":1,"pc":260,"access":{"address":65544,"bytes":4,"write":false},"lanes":[8,9,10,11],"data":"00000000112233440000000000000000"}
  {"type":"memory.access","cycle":3,"pc":264,"access":{"address":536870912,"bytes":4,"write":true},"lanes":[0,1,2,3],"data":"000000000000000000000000cafef00d"}
  {"type":"memory.fault","cycle":5,"pc":268,"address":805306368,"write":false,"request":{"cycle":4,"address":536870928}}
  {"type":"memory.access","cycle":4,"pc":268,"access":{"address":536870928,"bytes":4,"write":false},"lanes":[0,1,2,3],"data":"00000000000000000000000055667788"}
  {"type":"memory.fault","cycle":6,"pc":272,"address":64,"write":true}
  {"type":"memory.access","cycle":7,"pc":276,"access":{"address":536870944,"bytes":4,"write":false},"lanes":[0,1,2,3],"data":"00000000000000000000000000000000"}
  {"type":"diag","severity":"warning","source":"memory","code":"bind.unknown-bits","cycle":9,"time":20,"paths":["TOP.core.lsu.io_tlul_d_bits_data"],"message":"bits of xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}
  {"type":"memory.summary","reads":3,"writes":2,"pcs":5,"faults":2}

The same trace as an FST file, made from memory.vcd by tools/vcd2fst.sh (libfst's writer; the file
holds the date it was written, so regenerating changes its bytes, not its content):

  $ coralview memory --platform mem-core.json --format jsonl memory.fst | tail -n +2 > fst.jsonl
  $ coralview memory --platform mem-core.json --format jsonl memory.vcd | tail -n +2 | cmp - fst.jsonl

Accesses of 8 and 16 bytes print every byte of their data, a read of 16 bytes the line of its response (wide.vcd
is made by gen.sh wide):

  $ coralview memory --platform mem-core.json wide.vcd
  platform mem-core
         0 W pc 00000200 addr 00010008 8 bytes 8899aabbccddeeff
         1 W pc 00000204 addr 00010010 16 bytes 0102030405060708090a0b0c0d0e0f10
         2 R pc 00000208 addr 00010020 16 bytes 8f0e0d0c0b0a09080706050403020100
  root TOP.core: 1 read and 2 write requests from 3 PCs, 0 faults

The lanes follow the description's data bus, here 8 bytes (narrow.vcd is made by gen.sh narrow): a write of
the upper four bytes, and a read with no mask, whose lanes come from its address and size:

  $ coralview memory --platform mem8-core.json narrow.vcd
  platform mem8-core
         0 W pc 00000300 addr 00010008 8 bytes 8899aabbccddeeff
         1 W pc 00000304 addr 00010014 4 bytes cafef00d
         2 R pc 00000308 addr 00010028 4 bytes 55667788
  root TOP.core: 1 read and 2 write requests from 3 PCs, 0 faults
  $ coralview memory --platform mem8-core.json --format jsonl narrow.vcd | grep '"lanes"' | sed 's/"access.*"lanes"/"lanes"/'
  {"type":"memory.access","cycle":0,"pc":768,"lanes":[0,1,2,3,4,5,6,7],"data":"8899aabbccddeeff"}
  {"type":"memory.access","cycle":1,"pc":772,"lanes":[4,5,6,7],"data":"cafef00d00000000"}
  {"type":"memory.access","cycle":2,"pc":776,"lanes":[0,1,2,3],"data":"1122334455667788"}

A source that is requested again before its response replaces the first request, which the diagnostic
names (proto.vcd is made by gen.sh proto):

  $ coralview memory --platform mem-core.json --format jsonl proto.vcd | grep tlul.reopened
  {"type":"diag","severity":"warning","source":"memory","code":"tlul.reopened","cycle":1,"time":4,"paths":["TOP.core.lsu.io_tlul_a_bits_source"],"message":"source 1 requested again while its read of 00010008, accepted at cycle 0, is outstanding"}

A response for a source with nothing outstanding is counted and listed, where it came, and is a diagnostic
too:

  $ coralview memory --platform mem-core.json proto.vcd
  platform mem-core
         1 R pc 00000404 addr 0001000c 4 bytes 11223344
         3 unmatched response for source 5
  root TOP.core: 1 read and 0 write requests from 1 PCs, 0 faults, 1 unmatched
  $ coralview memory --platform mem-core.json --format jsonl proto.vcd | tail -n +2 | grep -v tlul.reopened
  {"type":"memory.access","cycle":1,"pc":1028,"access":{"address":65548,"bytes":4,"write":false},"lanes":[8,9,10,11],"data":"00000000112233440000000000000000"}
  {"type":"memory.unmatched","cycle":3,"source":5}
  {"type":"diag","severity":"warning","source":"memory","code":"tlul.unmatched","cycle":3,"time":8,"paths":["TOP.core.lsu.io_tlul_d_bits_source"],"message":"response for source 5 with nothing outstanding"}
  {"type":"memory.summary","reads":1,"writes":0,"pcs":1,"faults":0,"unmatched":1}
  $ coralview memory --platform mem-core.json --from-cycle 2 --to-cycle 4 proto.vcd
  platform mem-core
         3 unmatched response for source 5
  root TOP.core: 1 read and 0 write requests from 1 PCs, 0 faults, 1 unmatched
  window [2, 4]: 0 read and 0 write requests from 0 PCs, 0 faults, 1 unmatched
