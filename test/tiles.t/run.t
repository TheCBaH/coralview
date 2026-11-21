A tile load into tile 1 sub-tile 2, then two writes by the PE array into tile 3 sub-tile 0, the second
of its upper two bytes only:

  $ coralview tiles --platform tile-core.json tiles.vcd
  platform tile-core
         0 blk0 port0 load        tile  1 sub  2 mask 000f 11223344
         2 blk0 port0 pc 00000200 tile  3 sub  0 mask 000f aabbccdd
         3 blk0 port0 pc 00000200 tile  3 sub  0 mask 000c 55660000
  root TOP.core: 3 sub-tile writes; 2 of 256 sub-tiles written
    tile loads : 1 writes, cycles 0-0
    pc 00000200: 2 writes, cycles 2-3

In a window the writes and the PCs are the window's:

  $ coralview tiles --platform tile-core.json --from-cycle 2 tiles.vcd
  platform tile-core
         2 blk0 port0 pc 00000200 tile  3 sub  0 mask 000f aabbccdd
         3 blk0 port0 pc 00000200 tile  3 sub  0 mask 000c 55660000
  root TOP.core: 3 sub-tile writes; 2 of 256 sub-tiles written
  window [2, end]: 2 sub-tile writes; 1 of 256 sub-tiles written
    pc 00000200: 2 writes, cycles 2-3

As JSON lines; the summary holds each sub-tile's final content, the second write merged into the
first:

  $ coralview tiles --platform tile-core.json --format jsonl tiles.vcd | jq -c 'select(.type != "coralview")'
  {"type":"tiles.write","cycle":0,"block":0,"port":0,"tile":1,"sub":2,"mask":15,"data":"11223344"}
  {"type":"tiles.write","cycle":2,"block":0,"port":0,"pc":512,"tile":3,"sub":0,"mask":15,"data":"aabbccdd"}
  {"type":"tiles.write","cycle":3,"block":0,"port":0,"pc":512,"tile":3,"sub":0,"mask":12,"data":"55660000"}
  {"type":"tiles.summary","writes":3,"file":[{"tile":1,"sub":2,"data":"11223344"},{"tile":3,"sub":0,"data":"5566ccdd"}]}

The VME's write ports are named by the description: renamed in both, the listing is the same:

  $ coralview tiles --platform tile-core.json tiles.vcd > before.txt
  $ cat > rename.sed <<'SED'
  > s/\bwriteEn\b/we/g
  > s/\bpeWriteEn\b/pe_we/g
  > s/\bpeWritePc\b/pe_pc/g
  > s/\bwriteMtIdx\b/mt/g
  > s/\bwriteSubIdx\b/sub/g
  > s/\bwriteData\b/wdata/g
  > SED
  $ sed -f rename.sed tile-core.json > renamed-core.json
  $ sed -f rename.sed tiles.vcd > renamed.vcd
  $ coralview tiles --platform renamed-core.json renamed.vcd > after.txt
  $ diff before.txt after.txt

Wires that hold their values through a clock edge keep writing: a held write is a write in each cycle.
The trace with one more cycle after the second write, and nothing changing in it:

  $ awk '/^#/ { n = substr($0, 2) + 0; if (n > 8) { if (!done) { print "#9"; print "1ck"; print "#10"; print "0ck"; done = 1 } print "#" n + 2; next } } { print }' tiles.vcd > held.vcd
  $ coralview tiles --platform tile-core.json held.vcd | grep ' blk'
         0 blk0 port0 load        tile  1 sub  2 mask 000f 11223344
         2 blk0 port0 pc 00000200 tile  3 sub  0 mask 000f aabbccdd
         3 blk0 port0 pc 00000200 tile  3 sub  0 mask 000c 55660000
         4 blk0 port0 pc 00000200 tile  3 sub  0 mask 000c 55660000
