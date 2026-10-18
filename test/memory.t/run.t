Requests on the LSU's TCM and external buses: a TCM write and read, whose data comes the cycle after
the request, the same on the external bus, then two faults, the first with a request from its PC
before it and the second without, and a last read whose data is unknown:

  $ coralview memory --platform mem-core.json memory.vcd
         0 tcm W pc 00000100 addr 00010004 4 bytes deadbeef
         1 tcm R pc 00000104 addr 00010008 4 bytes 11223344
         3 ext W pc 00000108 addr 20000000 4 bytes cafef00d
         4 ext R pc 0000010c addr 20000010 4 bytes 55667788
         5 fault R pc 0000010c addr 30000000, requested at 4, addr 20000010
         6 fault W pc 00000110 addr 00000040, no request seen
         7 ext R pc 00000114 addr 20000020 4 bytes 00000000
  root TOP.core: 3 read and 2 write requests from 5 PCs, 2 faults

As JSON lines, with each request's byte lanes and its line of data; the unknown data is a
diagnostic line:

  $ coralview memory --platform mem-core.json --format jsonl memory.vcd
  {"type":"coralview","schema_version":1,"model":"memory","platform":"mem-core","trace":"memory.vcd"}
  {"type":"memory.access","cycle":0,"bus":"tcm","pc":256,"access":{"address":65540,"bytes":4,"write":true},"lanes":[4,5,6,7],"data":"0000000000000000deadbeef00000000"}
  {"type":"memory.access","cycle":1,"bus":"tcm","pc":260,"access":{"address":65544,"bytes":4,"write":false},"lanes":[8,9,10,11],"data":"00000000112233440000000000000000"}
  {"type":"memory.access","cycle":3,"bus":"external","pc":264,"access":{"address":536870912,"bytes":4,"write":true},"lanes":[0,1,2,3],"data":"000000000000000000000000cafef00d"}
  {"type":"memory.access","cycle":4,"bus":"external","pc":268,"access":{"address":536870928,"bytes":4,"write":false},"lanes":[0,1,2,3],"data":"00000000000000000000000055667788"}
  {"type":"memory.fault","cycle":5,"pc":268,"address":805306368,"write":false,"request":{"cycle":4,"address":536870928}}
  {"type":"memory.fault","cycle":6,"pc":272,"address":64,"write":true}
  {"type":"memory.access","cycle":7,"bus":"external","pc":276,"access":{"address":536870944,"bytes":4,"write":false},"lanes":[0,1,2,3],"data":"00000000000000000000000000000000"}
  {"type":"diag","severity":"warning","source":"memory","code":"bind.unknown-bits","cycle":8,"time":18,"paths":["TOP.core.lsu.io_ebus_dbus_rdata"],"message":"bits of xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}
  {"type":"memory.summary","reads":3,"writes":2,"pcs":5,"faults":2}
