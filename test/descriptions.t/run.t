Platform description errors point at the offending block in the file. Every
case here reads a fixture of another test and breaks one thing in it; the
description is read before the trace, so any trace will do:

  $ t=..
  $ v=$t/platform.t/core.vcd

A wire name without %d for a block of several lanes, and a list of names with
the wrong length:

  $ sed -e 's/"lanes": 1,/"lanes": 2,/g' -e 's/io_debug_dispatch_%d_inst/dp_/g' $t/platform.t/test-core.json > nolane.json
  $ coralview check --platform nolane.json $v
  dispatch_debug: "dp_Fire" has no %d for its 2 lanes
  File "nolane.json", lines 10-11, characters 22-63:
  File "nolane.json", line 10, characters 4-20: in member dispatch_debug of
  File "nolane.json", lines 9-11, characters 12-64: blocks object
  File "nolane.json", line 9, characters 2-10: in member blocks of
  File "nolane.json", lines 1-11, characters 0-64: platform object
  [2]
  $ sed 's/"try_dispatch": \["tryDispatch", "tryDispatch_1"\]/"try_dispatch": ["tryDispatch"]/' $t/stalls.t/stall-core.json > nolist.json
  $ coralview check --platform nolist.json $v
  dispatch.try_dispatch: 1 names for 2 lanes
  File "nolist.json", lines 10-18, characters 16-5:
  File "nolist.json", line 10, characters 4-14: in member dispatch of
  File "nolist.json", lines 9-19, characters 12-3: blocks object
  File "nolist.json", line 9, characters 2-10: in member blocks of
  File "nolist.json", lines 1-19, characters 0-3: platform object
  [2]

A TileLink port or an AXI port whose data bus is not a power of two bytes wide,
an AXI source id given twice, an origin whose alignment is not, and a DMA
engine whose host port is too narrow for its descriptors:

  $ sed 's/"data_bytes": 16/"data_bytes": 12/' $t/memory.t/mem-core.json > tl12.json
  $ coralview check --platform tl12.json $v
  tlul: data_bytes 12 is not a power of two
  File "tl12.json", line 10, characters 39-99:
  File "tl12.json", line 10, characters 31-37: in member port of
  File "tl12.json", line 10, characters 11-100: lsu object
  File "tl12.json", line 10, characters 4-9: in member lsu of
  File "tl12.json", lines 9-10, characters 12-100: blocks object
  File "tl12.json", line 9, characters 2-10: in member blocks of
  File "tl12.json", lines 1-10, characters 0-100: platform object
  [2]
  $ sed 's/"data_bytes": 16/"data_bytes": 24/' $t/axi.t/axi-core.json > axi24.json
  $ coralview check --platform axi24.json $v
  axi_master: data_bytes 24 is not a power of two
  File "axi24.json", lines 17-29, characters 18-5:
  File "axi24.json", line 17, characters 4-16: in member axi_master of
  File "axi24.json", lines 9-30, characters 12-3: blocks object
  File "axi24.json", line 9, characters 2-10: in member blocks of
  File "axi24.json", lines 1-30, characters 0-3: platform object
  [2]
  $ sed 's/"id": 1,/"id": 0,/' $t/axi.t/axi-core.json > axidup.json
  $ coralview check --platform axidup.json $v
  axi_master: a source id is given twice
  File "axidup.json", lines 17-29, characters 18-5:
  File "axidup.json", line 17, characters 4-16: in member axi_master of
  File "axidup.json", lines 9-30, characters 12-3: blocks object
  File "axidup.json", line 9, characters 2-10: in member blocks of
  File "axidup.json", lines 1-30, characters 0-3: platform object
  [2]
  $ sed 's/"align": 16/"align": 3/' $t/axi.t/axi-core.json > align3.json
  $ coralview check --platform align3.json $v
  origin: align 3 is not a power of two
  File "align3.json", line 27, characters 20-123:
  File "align3.json", line 27, characters 10-18: in member origin of
  File "align3.json", lines 26-27, characters 8-125: axi source object
  File "align3.json", lines 26-27, characters 8-125: at index 1 of
  File "align3.json", lines 19-27, characters 17-125: array<axi source object>
  File "align3.json", line 19, characters 6-15: in member sources of
  File "align3.json", lines 17-27, characters 18-125: axi_master object
  File "align3.json", line 17, characters 4-16: in member axi_master of
  File "align3.json", lines 9-27, characters 12-125: blocks object
  File "align3.json", line 9, characters 2-10: in member blocks of
  File "align3.json", lines 1-27, characters 0-125: platform object
  [2]
  $ sed 's/"host": { "prefix": "io_tl_host_", "data_bytes": 16/"host": { "prefix": "io_tl_host_", "data_bytes": 8/' $t/dma.t/dma-sub.json > dma8.json
  $ coralview check --platform dma8.json $v
  dma: the host port carries 16-byte descriptor halves
  File "dma8.json", lines 10-17, characters 11-5:
  File "dma8.json", line 10, characters 4-9: in member dma of
  File "dma8.json", lines 9-18, characters 12-3: blocks object
  File "dma8.json", line 9, characters 2-10: in member blocks of
  File "dma8.json", lines 1-18, characters 0-3: platform object
  [2]

A register file with fewer scoreboard entries than registers, a vector
register file whose write layout lacks a field or whose width is no multiple of
eight bits, and a vector dispatch layout that lacks a field:

  $ sed '/"first": 1,/s/"scoreboard_entries": 32/"scoreboard_entries": 3/' $t/registers.t/reg-core.json > small.json
  $ coralview check --platform small.json $v
  register file: 3 scoreboard entries for registers up to 3
  File "small.json", lines 17-26, characters 19-5:
  File "small.json", line 17, characters 4-17: in member x_registers of
  File "small.json", lines 9-26, characters 12-6: blocks object
  File "small.json", line 9, characters 2-10: in member blocks of
  File "small.json", lines 1-26, characters 0-6: platform object
  [2]
  $ grep -v rt_data $t/vectors.t/vector-core.json > nodata.json
  $ coralview check --platform nodata.json $v
  v_registers.writes.layout: no rt_data
  File "nodata.json", lines 17-29, characters 19-5:
  File "nodata.json", line 17, characters 4-17: in member v_registers of
  File "nodata.json", lines 9-30, characters 12-3: blocks object
  File "nodata.json", line 9, characters 2-10: in member blocks of
  File "nodata.json", lines 1-30, characters 0-3: platform object
  [2]
  $ sed 's/"vlen": 16/"vlen": 12/' $t/vectors.t/vector-core.json > vlen12.json
  $ coralview check --platform vlen12.json $v
  v_registers: vlen 12 is not a multiple of 8
  File "vlen12.json", lines 17-30, characters 19-5:
  File "vlen12.json", line 17, characters 4-17: in member v_registers of
  File "vlen12.json", lines 9-31, characters 12-3: blocks object
  File "vlen12.json", line 9, characters 2-10: in member blocks of
  File "vlen12.json", lines 1-31, characters 0-3: platform object
  [2]
  $ grep -v csr_vl $t/ops.t/ops-core.json > novl.json
  $ coralview check --platform novl.json $v
  v_dispatch.layout: no csr_vl
  File "novl.json", lines 12-24, characters 18-5:
  File "novl.json", line 12, characters 4-16: in member v_dispatch of
  File "novl.json", lines 9-25, characters 12-3: blocks object
  File "novl.json", line 9, characters 2-10: in member blocks of
  File "novl.json", lines 1-25, characters 0-3: platform object
  [2]
