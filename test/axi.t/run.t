A load's external read waits a cycle for the address channel; an instruction fetch from external RAM
overlaps it on ID 1 and is answered first. Two instances of a store queue in the LSU and both retire
before the second makes its request; the queue pins each write to its own instance. The first store's
data is accepted before its address. A write response arrives for an ID with nothing outstanding, and
the last read is not the address the LSU asked for and is never answered:

  $ coralview axi --platform axi-core.json --profile 3 axi.vcd
     start   accept     done dir  id source addr                 bytes beats B/cycle out  origin
         1        3        6 R     0 lsu    20000000                16  1x16    2.67   1  pc 00000100 lw x10, 0(x10) (dispatched 0, op 1, retired 7)
         3        4        5 R     1 fetch  20001000                16  1x16    5.33   2  request 20001004
         8        9       11 W     0 lsu    20000010                 4  1x16    1.00   1  pc 00000104 sw x11, 16(x10) (dispatched 7, op 8, retired 9)
        13       13       15 W     0 lsu    20000014                 4  1x16    1.33   1  pc 00000104 sw x11, 16(x10) (dispatched 8, op 12, retired 10)
        17       18        - R     0 lsu    20000030                 0  1x16       -   1  pc 00000108 lw x10, 32(x10) (dispatched 16, op 17, retired -); DISAGREES: request R 20000020
        16 unmatched W id 3: write response with no outstanding write
  root TOP.core: reads 3 (32 bytes), writes 2 (8 bytes) in 21 cycles, unmatched 1
    latency, address accepted to done, min/mean/max: reads 1/2.0/3, writes 2/2.0/2 cycles; 1 not done when the trace ends
    throughput 2.000 bytes/cycle over cycles 1-20, 3.077 while a transaction is outstanding (13 cycles)
    outstanding at once: max 2 (reads 2, writes 1); cycles by count: 0:5 1:11 2:2
    source lsu (id 0): transactions 4, bytes 24, pinned to a request 4, to an instruction instance 4, DISAGREEING 1
    source fetch (id 1): transactions 1, bytes 16, pinned to a request 1, to an instruction instance 0
  external traffic by instruction:
        pc  count   bytes  cycles  instruction
  00000100      1      16       6  lw x10, 0(x10)
  00000104      2       8       7  sw x11, 16(x10)
  00000108      1       0       0  lw x10, 32(x10)

Without the LSU's PC the description does not match the trace:

  $ sed 's/"io_ebus_dbus_pc"/"io_ebus_dbus_pc_q"/' axi-core.json > renamed.json
  $ coralview axi --platform renamed.json axi.vcd
  platform axi-core does not match the trace (model axi):
    missing io_ebus_dbus_pc_q
  [3]
