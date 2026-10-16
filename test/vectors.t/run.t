A two-register, 16-bit vector register file with two write ports. In cycle 2
both ports write v0, each one byte, and the RTL ORs them. In cycle 3 one
instruction writes all of v1 and the high byte of v0, while the previous
one retires v0. Each instruction retires a cycle after its writes:

  $ coralview vectors --platform vector-core.json vectors.vcd
         1 port0 pc 00000100 v0  strobe 1 00ab
         2 port0 pc 00000104 v0  strobe 2 cd00
         2 port1 pc 00000104 v0  strobe 1 0011
         3 port0 pc 00000108 v0  strobe 2 ee00
         3 port1 pc 00000108 v1  strobe 3 beef
  root TOP.core: 7 cycles, 5 vector register writes from 3 PCs
    pc 00000100: 1 writes to v0, cycles 1-1
    pc 00000104: 2 writes to v0, cycles 2-2
    pc 00000108: 2 writes to v0 v1, cycles 3-3
  vectors.storage                   4 comparisons, 0 failures
  vectors.retired                   3 comparisons, 0 failures
  storage at the end:
    v0   ee11
    v1   beef

The storage keeps the old low byte of v0 instead of port 1's write, and the
instruction retiring v1 is not the one that wrote it:

  $ coralview vectors --platform vector-core.json --limit 0 bad.vcd
  root TOP.core: 7 cycles, 5 vector register writes from 3 PCs
    pc 00000100: 1 writes to v0, cycles 1-1
    pc 00000104: 2 writes to v0, cycles 2-2
    pc 00000108: 2 writes to v0 v1, cycles 3-3
  vectors.storage                   4 comparisons, 1 failures
  vectors.retired                   3 comparisons, 1 failures
  storage at the end:
    v0   eeab
    v1   beef
  error[vectors.storage] vectors cycle 3 time 8: key 64: v0 byte 0 holds ab, last written 11
  error[vectors.retired] vectors cycle 4 time 10: pc 0000010c retired v1, last written at cycle 3 by pc 00000108
  [1]

A layout without the byte enables is not a vector register file:

  $ sed 's/"rt_strobe"/"rt_mask"/' vector-core.json > no-strobe.json
  $ coralview vectors --platform no-strobe.json vectors.vcd
  v_registers.writes.layout: no rt_strobe
  File "no-strobe.json": in member v_registers of
  File "no-strobe.json", lines 9-27, characters 12-3: blocks object
  File "no-strobe.json": in member blocks of
  File "no-strobe.json", lines 1-27, characters 0-3: platform object
  [2]
