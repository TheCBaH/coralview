A trace of `addi x10, x0, 3` and then three trips of a two-instruction loop (`addi x10, x10, -1`;
`bne x10, x0, -4`). The first trip waits eight cycles for its first instruction:

  $ coralview commits --platform loop-core.json --limit 10 loop.vcd | sed -n 3,9p
         3 0 80000000 00300513 addi x10, x0, 3                                     3   -   4
        11 0 80000004 fff50513 addi x10, x10, -1                                   3   -   4
        12 0 80000008 fe051ee3 bne x10, x0, -4                                     3   -   1
        14 0 80000004 fff50513 addi x10, x10, -1                                   3   -   2
        15 0 80000008 fe051ee3 bne x10, x0, -4                                     3   -   1
        17 0 80000004 fff50513 addi x10, x10, -1                                   3   -   2
        18 0 80000008 fe051ee3 bne x10, x0, -4                                     3   -   1

  $ coralview loops --platform loop-core.json loop.vcd
  platform test-core
  loop 80000004, back edge at 80000008: 3 trips
    instructions a trip 2 (2..2)
    cycles a trip 3 (3..5)
    cycles by trip: 5 3 3
          pc  count cyc/trip  instruction
    80000004      3    2.67  addi x10, x10, -1
    80000008      3    1.00  bne x10, x0, -4

As JSON lines, the trips with their start cycle, and the PCs with their totals:

  $ coralview loops --platform loop-core.json --format jsonl loop.vcd
  {"type":"coralview","schema_version":2,"model":"loops","platform":"test-core","trace":"loop.vcd"}
  {"type":"loops.loop","header":2147483652,"tail":2147483656,"trips":[{"start":11,"instructions":2,"cycles":5},{"start":14,"instructions":2,"cycles":3},{"start":17,"instructions":2,"cycles":3}],"pcs":[{"pc":2147483652,"word":4294247699,"count":3,"cycles":8},{"pc":2147483656,"word":4261748451,"count":3,"cycles":3}]}

With the ELF the header PC gets its function; a window leaves out the trips before it (a trip
that began before the window is not found):

  $ ../../tools/mkelf.exe loop.elf 80000000 start:4 body:8
  $ coralview loops --platform loop-core.json --elf loop.elf loop.vcd | sed -n 2p
  loop 80000004 <body>, back edge at 80000008: 3 trips
  $ coralview loops --platform loop-core.json --from-cycle 14 loop.vcd | sed -n 2,5p
  loop 80000004, back edge at 80000008: 2 trips
    instructions a trip 2 (2..2)
    cycles a trip 3 (3..3)
    cycles by trip: 3 3
