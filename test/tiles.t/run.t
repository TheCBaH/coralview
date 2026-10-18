A tile load into tile 1 sub-tile 2, then two writes by the PE array into tile 3 sub-tile 0, the second
of its upper two bytes only:

  $ coralview tiles --platform tile-core.json tiles.vcd
         0 blk0 port0 load        tile  1 sub  2 mask 000f 11223344
         2 blk0 port0 pc 00000200 tile  3 sub  0 mask 000f aabbccdd
         3 blk0 port0 pc 00000200 tile  3 sub  0 mask 000c 55660000
  root TOP.core: 3 sub-tile writes; 2 of 256 sub-tiles written
    tile loads : 1 writes, cycles 0-0
    pc 00000200: 2 writes, cycles 2-3

As JSON lines; the summary holds each sub-tile's final content, the second write merged into the
first:

  $ coralview tiles --platform tile-core.json --format jsonl tiles.vcd | jq -c 'select(.type != "coralview")'
  {"type":"tiles.write","cycle":0,"block":0,"port":0,"tile":1,"sub":2,"mask":15,"data":"11223344"}
  {"type":"tiles.write","cycle":2,"block":0,"port":0,"pc":512,"tile":3,"sub":0,"mask":15,"data":"aabbccdd"}
  {"type":"tiles.write","cycle":3,"block":0,"port":0,"pc":512,"tile":3,"sub":0,"mask":12,"data":"55660000"}
  {"type":"tiles.summary","writes":3,"file":[{"tile":1,"sub":2,"data":"11223344"},{"tile":3,"sub":0,"data":"5566ccdd"}]}
