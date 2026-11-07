`cost` joins the commits of a trace with its memory requests. An addi
retires in cycle 4 and a store to the TCM in cycle 5; the store's request
is made in cycle 3, between its dispatch and retirement:

  $ coralview cost --platform cost-core.json cost.vcd
  platform cost-core
  class        region      count  cycles     d->r
  alu          -               1       4     3.00
  mem          tcm             1       1     3.00

A window selects the retirements it covers and states itself in the header:

  $ coralview cost --platform cost-core.json --format jsonl --between-pc 80000000,80000004 cost.vcd
  {"type":"coralview","schema_version":2,"model":"cost","platform":"cost-core","trace":"cost.vcd","window":{"first":4,"last":5,"pcs":[]}}
  {"type":"cost.row","class":"alu","region":"-","count":1,"cycles":4,"d_to_r":3}
  {"type":"cost.row","class":"mem","region":"tcm","count":1,"cycles":1,"d_to_r":3}

  $ coralview cost --platform cost-core.json --format jsonl --from-cycle 5 cost.vcd
  {"type":"coralview","schema_version":2,"model":"cost","platform":"cost-core","trace":"cost.vcd","window":{"first":5,"pcs":[]}}
  {"type":"cost.row","class":"mem","region":"tcm","count":1,"cycles":1,"d_to_r":3}

`--entry` drops what runs before a function, here the addi before the store:

  $ ../../tools/mkelf.exe cost.elf 80000000 startup:4 kernel:4
  $ coralview cost --platform cost-core.json --elf cost.elf --entry kernel cost.vcd
  platform cost-core
  class        region      count  cycles     d->r
  mem          tcm             1       1     3.00
