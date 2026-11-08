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
