`cost` joins the commits of a trace with its memory requests. An addi
retires in cycle 4 and a store to the TCM in cycle 5; the store's request
is made in cycle 3, between its dispatch and retirement:

  $ coralview cost --platform cost-core.json cost.vcd
  platform cost-core
  class        region      count  cycles     d->r
  alu          -               1       4     3.00
  mem          mem             1       1     3.00

A window selects the retirements it covers and states itself in the header:

  $ coralview cost --platform cost-core.json --format jsonl --between-pc 80000000,80000004 cost.vcd
  {"type":"coralview","schema_version":3,"model":"cost","platform":"cost-core","trace":"cost.vcd","window":{"first":4,"last":5,"pcs":[]}}
  {"type":"cost.row","class":"alu","region":"-","count":1,"cycles":4,"d_to_r":3}
  {"type":"cost.row","class":"mem","region":"mem","count":1,"cycles":1,"d_to_r":3}

  $ coralview cost --platform cost-core.json --format jsonl --from-cycle 5 cost.vcd
  {"type":"coralview","schema_version":3,"model":"cost","platform":"cost-core","trace":"cost.vcd","window":{"first":5,"pcs":[]}}
  {"type":"cost.row","class":"mem","region":"mem","count":1,"cycles":1,"d_to_r":3}

A window that is not found is an error, before anything is printed. The window is found in the run
that prints it, so a pipe serves as well as a file:

  $ coralview cost --platform cost-core.json --between-pc 90000000,80000000 cost.vcd
  --between-pc: pc 90000000 retires fewer than 1 times
  [3]
  $ coralview cost --platform cost-core.json --between-pc 80000000,80000004 - < cost.vcd
  platform cost-core
  class        region      count  cycles     d->r
  alu          -               1       4     3.00
  mem          mem             1       1     3.00

`--entry` drops what runs before a function, here the addi before the store:

  $ ../../tools/mkelf.exe cost.elf 80000000 startup:4 kernel:4
  $ coralview cost --platform cost-core.json --elf cost.elf --entry kernel cost.vcd
  platform cost-core
  class        region      count  cycles     d->r
  mem          mem             1       1     3.00

`summary` gives the figures of a window in one record: the instructions and cycles charged, the data
requests, and (on platforms that have those models) vector operations and dispatch stall reasons:

  $ coralview summary --platform cost-core.json cost.vcd
  platform cost-core
  window [0, end]
    instructions 2, cycles charged 5
    data requests: 0 loads, 1 stores
  $ coralview summary --platform cost-core.json --format jsonl --from-cycle 5 cost.vcd
  {"type":"coralview","schema_version":3,"model":"summary","platform":"cost-core","trace":"cost.vcd","window":{"first":5,"pcs":[]}}
  {"type":"summary.window","first":5,"instructions":1,"cycles":1,"loads":0,"stores":0}

The markers work on a pipe for `summary` as they do on a file:

  $ coralview summary --platform cost-core.json --elf cost.elf --entry kernel - < cost.vcd
  platform cost-core
  window [5, end]
    instructions 1, cycles charged 1
    data requests: 0 loads, 0 stores

and for `run`, whose views and sinks are made once the window is found:

  $ coralview run --platform cost-core.json --model commits --model memory --between-pc 80000000,80000004 - < cost.vcd
  platform cost-core
     cycle L pc       word     instruction                      dest             d>r d>w chg
         4 0 80000000 02a00513 addi x10, x0, 42                 x10=0000002a       3   2   4
         5 0 80000004 00a5a023 sw x10, 0(x11)                                      3   -   1
  root TOP.core: 8 cycles, 1 before the first dispatch, 2 later with nothing in flight; 0 retires without dispatch, 0 dispatches skipped with 0 cycles charged, 0 values missing, 0 in flight at the end
  window [4, 5]: 2 commits, 5 cycles charged
  platform cost-core
  root TOP.core: 0 read and 1 write requests from 1 PCs, 0 faults
  window [4, 5]: 0 read and 0 write requests from 0 PCs, 0 faults
  $ coralview run --platform cost-core.json --model memory --between-pc 80000000,80000004 --sink memory:jsonl:- - < cost.vcd | cut -c1-110
  {"type":"coralview","schema_version":3,"model":"memory","platform":"cost-core","trace":"-","window":{"first":4
  {"type":"memory.summary","reads":0,"writes":1,"pcs":1,"faults":0}
  $ coralview run --platform cost-core.json --model memory --between-pc 90000000,80000000 --sink memory:jsonl:out.jsonl - < cost.vcd
  --between-pc: pc 90000000 retires fewer than 1 times
  [3]
  $ test -e out.jsonl && echo written
  [1]
  $ coralview run --platform cost-core.json --model commits --between-pc 80000000,80000004 --kanata - - < cost.vcd | head -n 4
  Kanata	0004
  C=	1
  I	0	0	0
  L	0	0	80000000 addi x10, x0, 42
