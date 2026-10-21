# Observing the Coral NPU from its waveforms

coralview reads the FST traces of the Coral NPU RTL simulators. Its models
show these for each run:

- what each instruction did and how long it took;
- why dispatch stalled;
- what the load/store unit read and wrote;
- what the matrix engine (VME) wrote into its tile registers;
- the contents of the x and f register files, checked against what was
  written and what retired;
- the vector register file, checked against its write ports, with the PC
  of each write;
- each fault, the CSR update it causes and whether its handler ran.

All of them are [hwfrp](../hwfrp/README.md) graphs, bound to the trace through a
platform description.

- [Where the traces come from](#where-the-traces-come-from)
- [Platform descriptions](#platform-descriptions)
- [Blocks observed](#blocks-observed)
- [Models](#models): `commits`, `stalls`, `memory`, `tiles`, `ops`,
  `registers`, `vectors`, `traps`
- [Any signal, over a window](#any-signal-over-a-window)
- [Execution time of each instruction](#execution-time-of-each-instruction)
- [Not observed yet](#not-observed-yet)

## Where the traces come from

The devcontainer image holds the simulators of devcontainer.coralnpu
release `v0.0.4` under `/opt/coralnpu`. Each is the Verilator build of one
Coral NPU configuration with the SystemC testbench, plus example ELFs.
`--trace` writes an FST of the whole hierarchy: every signal of every
module, not just the ports. The VME core's trace of `matrix.elf` has:

- 159,567 variables in 26,541 scopes (79,512 distinct signals);
- 2,169 timestamps for 1,084 cycles;
- a size of 1.15 MB.

```sh
/opt/coralnpu/emulators/bin/vme_core_mini_axi_sim --trace \
  --binary=/opt/coralnpu/emulators/examples/matrix.elf
coralview commits --platform vme-core-mini-axi --profile 10 /tmp/VVmeCoreMiniAxi.core.fst
```

The full-subsystem simulators (`/opt/coralnpu/subsystem/bin/Vchip_*`:
SRAM, ROM, peripherals and the DMA engine around the core) take their
program in two steps: `--load_elf` writes it into memory, and the
archive's `tools/loader.py` starts the core over the SPI DPI port.
`tools/trace-subsystem.sh` does both with `--trace` and leaves `sim.fst`.
The subsystem core has no debug ports, so only the `dma` model applies.

```sh
s=/opt/coralnpu/subsystem
tools/trace-subsystem.sh $s vector_normal $s/examples/subsystem_dma.elf 8 32 /tmp/sub
coralview dma --platform subsystem-vector-normal --manifest $s/hardware-configurations.json /tmp/sub/sim.fst
```

The testbench dumps at both clock edges, so a timestamp is an edge, not a
cycle. Every model therefore samples the core clock `io_aclk` after its
falling edge, when the values are settled.

## Platform descriptions

coralview does not search a trace for what it might contain. A *platform
description* says, for each RTL configuration:

- where the core's scope is;
- which blocks can be observed;
- their scopes, lane and port counts, and the names of the wires that
  differ between cores.

Every signal a model binds follows from that description. A signal it names
but the trace lacks is a hard error: exit status 3, with the path and what
was expected. That means coralview's understanding of the hardware is
wrong, not that the trace has less to offer.

The descriptions are JSON, parsed with `jsont`; unknown members are errors.
Three files describe the seven RTL configurations of the release:

| File | Configurations | Blocks |
|---|---|---|
| `core-mini.json` | `core-mini-axi`, `core-mini-highmem-axi`, `core-mini-itcm512kb-dtcm512kb-axi` | dispatch and retirement debug ports, x/f writeback, scalar dispatch, LSU |
| `rvv-core-mini.json` | `rvv-core-mini-axi`, `-highmem-axi`, `-itcm512kb-dtcm512kb-axi` | the same, with the RVV queue and per-lane float scoreboards |
| `vme-core-mini.json` | `vme-core-mini-axi` | the same, plus the VME tile register file |

An excerpt of `rvv-core-mini.json`:

```json
{
  "schema_version": "1.0",
  "name": "rvv-core-mini",
  "configurations": [
    { "name": "rvv-core-mini-axi", "top_level": "RvvCoreMiniAxi",
      "trace_root": ["VRvvCoreMiniAxi.core", "RvvCoreMiniAxi"] }
  ],
  "clock": "io_aclk",
  "sample": "after_falling",
  "blocks": {
    "retirement_debug": { "scope": [], "lanes": 8, "idx_width": 7, "trap": true },
    "dispatch": {
      "scope": ["core", "score", "dispatch"],
      "lanes": 4,
      "try_dispatch": ["tryDispatch", "tryDispatch_1", "tryDispatch_2", "tryDispatch_3"],
      "comb": ["io_scoreboard_comb", "comb_1", "comb_2", "comb_3"],
      "fcomb": ["io_fscoreboard", "fcomb_1", "fcomb_2", "fcomb_3"],
      "rvv_queue": "io_rvvQueueCapacity"
    }
  }
}
```

The cores differ in exactly such details:

- The scalar `core-mini` build keeps no per-lane float scoreboard wires,
  so its `fcomb` names `io_fscoreboard` for every lane: lanes 1–3 then do
  not see float writes by older lanes of the same cycle.
- Each configuration has its own trace root. The highmem variants are
  `CoreMiniHighmemAxi`, for example, not `CoreMiniAxi`.

A configuration's `name` and `top_level` match the archive's
`hardware-configurations.json`. `coralview platforms --manifest
/opt/coralnpu/emulators/hardware-configurations.json` checks that:

- every configuration exists with that top level;
- the VME block's tile count equals the manifest's `tile_registers`.

The manifest also supplies the memory region names in the `memory`
output.

Validated so far:

- `platforms --manifest` passes for all seven configurations.
- `check` binds every probe on traces from six of them: `core-mini-axi`
  (`scalar.elf`, `memory.elf`), `core-mini-highmem-axi`,
  `core-mini-itcm512kb-dtcm512kb-axi`, `rvv-core-mini-axi` (`rvv.elf`,
  `rvv_fp.elf`), `rvv-core-mini-itcm512kb-dtcm512kb-axi` and
  `vme-core-mini-axi`.
- `rvv-core-mini-highmem-axi` has no trace yet; its root is inferred from
  the others.

## Blocks observed

All paths are relative to the configuration's root, e.g.
`VVmeCoreMiniAxi.core.VmeCoreMiniAxi`.

| Block | Where | Signals | What they capture |
|---|---|---|---|
| `dispatch_debug` | top-level `io_debug_dispatch_{0..3}_*` (Coral patches 0003/0006/0011) | `instFire`, `instAddr`, `instInst` | each instruction leaving decode for an execution unit: lane, PC, word |
| `retirement_debug` | top-level `io_debug_rb_inst_{0..7}_*` | `valid`, `bits_pc`, `bits_idx`, `bits_trap` | instructions retiring from the 16-entry retirement buffer, up to 8 per cycle, with the unified destination index (x 0–31, f 32–63, v 64+, 126 store, 127 none) |
| `regfile_writeback` | `io_debug_regfile_writeData_{0..5}_*` | `valid`, `bits_addr`, `bits_data` | integer register file writes |
| `float_writeback` | `io_debug_float_writeData_{0,1}_*` | the same | float register file writes |
| `dispatch` | `core.score.dispatch` | `io_inst_N_{valid,ready,bits_addr,bits_inst}`, the `tryDispatch*` wires, the `comb*`/`fcomb*` scoreboards, `io_scoreboard_regd`, `io_halted`, `io_interlock`, `io_retirement_buffer_{nSpace,empty,trap_pending}`, `io_lsuQueueCapacity`, `io_rvvQueueCapacity` | the inputs and intermediate wires of `Dispatch.canDispatch` in `scalar/Decode.scala` |
| `lsu` | `core.score.lsu` | `io_dbus_*` (TCM), `io_ebus_dbus_*` (external), `io_ebus_dbus_pc`, `io_fault_*` | every data access the scalar LSU slot requests, with its PC, and its faults |
| `axi_master` | top-level `io_axi_master_*`; originators `core.score.lsu` (`io_ebus_dbus_*`, the queue `io_req_N_{valid,ready,bits_pc}`, `slot.io_uop_{valid,ready,bits_pc}`) and `core` (`io_ibus_*`) | the five AXI4 channels (`{read,write}_addr_bits_{addr,id,len,size,burst}`, `read_data_bits_{id,resp,last}`, `write_data_bits_{strb,last}`, `write_resp_bits_{id,resp}`) | every transaction leaving the core for external memory, and the request and instruction it serves |
| `dma` | the subsystem's `dma` (`bus.DmaEngine`); requester `rvv_core.coreAxi.core.score.lsu` | TileLink-UL `io_tl_host_{a,d}_*` (descriptor fetches, polls, data beats) and `io_tl_device_{a,d}_*` (CSRs; no `d_ready`) | every DMA job, from the CSR write that starts it to the status read that sees it done |
| `vme` | `core.rvvCore.rvvCoreWrapper.core.backend.vme` | `writeEn`, `peWriteEn`, `peWritePc`, `writeMtIdx`, `writeSubIdx`, `writeData` | writes into the 16 × 16 × 16-byte tile register file, per block (4) and port (4), tagged with the PC of the PE-array instruction |
| `x_registers`, `f_registers` | `core.score.regfile`, `core.score.fRegfile`, and the top-level `io_debug_*_writeAddr` marks | the registers (`regfile_N`; `fregfile_N_{sign,exponent,mantissa}`), `scoreboard`, `flushed_scoreboard`, `io_pipelineFlush` | the register files' contents and their pending-write bookkeeping |
| `v_registers` | `core.rvvCore.rvvCoreWrapper.core.backend.u_vrf` | `vrf_rd_data_full`, `rt2vrf_wr_valid`, `rt2vrf_wr_data` (4 × `RT2VRF_t`, laid out in the description) | the vector registers and every write to them, with its byte enables and PC |
| `v_dispatch` | `core.rvvCore.rvvCoreWrapper.core.backend` | `uop_valid_uop2dp`, `uop_ready_dp2uop`, `uop_uop2dp` (3 × `UOP_QUEUE_t`, laid out in the description) | every uop the backend dispatches, with its execution unit, PC and the `vl`/`vstart`/`sew`/`lmul` it runs with |
| `traps` | `core.score.fault_manager`, `core.score.csr` | `io_out_{valid,bits_mcause,bits_mepc,bits_mtval,bits_decode}`, `io_in_memory_fault_{valid,bits_write}`, `io_in_fetchFault_valid`, `io_in_rvv_fault_valid`; `mcause`, `mepc`, `mtval`, `mtvec` | faults as the fault manager raises them, and the CSRs they write |

The mini cores zero the retirement buffer's own `inst`, `data`, `vecWrites`
and `tileWrites` debug fields (`MuxOR(valid && !mini.B, …)` in
`RetirementBuffer.scala`). That is why the word and the values come from
other blocks.

## Models

`coralview platforms` lists, for each configuration, the models whose
blocks it has. `coralview check --platform P FILE` binds them all without
simulating, and lists every probe with its width and purpose.

### commits: what each instruction did

Blocks: `dispatch_debug`, `retirement_debug`, `regfile_writeback` (and
`float_writeback` when described). One `hwfrp` `Machine`, stepped every
cycle on the cycle's dispatched, written and retired lanes, keeps:

- **the instructions in flight, in dispatch order.** Dispatch is in
  program order, so a retirement takes the oldest entry with its PC; that
  entry supplies the word;
- **a queue of written values per register.** A retirement whose
  destination index is a register takes the oldest value written to it.
  The scoreboard keeps writes to one register in order;
- **a charge per cycle,** given to the oldest instruction in flight, so
  that the charges add up to the run's cycles.

```
$ coralview commits --platform vme-core-mini-axi --limit 6 --profile 5 matrix.fst
     407 0 00000000 b0205073 .word 0xb0205073                                    1   -   2
     409 0 00000004 b8205073 .word 0xb8205073                                    1   -   2
     411 0 00000008 b0202573 .word 0xb0202573                 x10=00000000       1   1   2
     413 0 0000000c b82025f3 .word 0xb82025f3                 x11=00000000       1   1   2
     414 0 00000010 00018117 auipc x2, 24                     x2=00018010        1   1   1
     415 0 00000014 ff010113 addi x2, x2, -16                 x2=00018000        1   1   1
root VVmeCoreMiniAxi.core.VmeCoreMiniAxi: 1084 cycles, 406 before the first dispatch, 18 later
with nothing in flight; 0 retires without dispatch, 0 dispatches skipped, 10 values missing, 0 in
flight at the end
      pc  count  cycles  share     d->r  instruction
0000023c      1      23   2.1%    22.00  vtse32 x12, 0(x2)
000001fc      1      20   1.8%    21.00  vtse32 x12, 0(x2)
000004e4      4      16   1.5%     4.00  beq x14, x0, 40
000002bc      1      16   1.5%    23.00  vtse32 x13, 0(x2)
000001b8      1      15   1.4%    27.00  vtse32 x12, 0(x2)
```

The columns are:

1. retirement cycle;
2. lane;
3. PC;
4. word;
5. disassembly by Rivet, with Coral's Zvt matrix instructions from the
   MPACT-derived `src/riscv/zvt.jsonl`; `.word` where Rivet has no form,
   such as the CSR instructions and Coral's `mpause`;
6. destination and value;
7. dispatch→retire cycles;
8. dispatch→writeback cycles;
9. cycles charged.

The "10 values missing" are the vector loads: their results go to the
vector register file, which the mini cores do not expose at retirement.

The vector values are in `vectors`, by PC.

**Selecting rows.** `--from-cycle`, `--to-cycle` and `--pc` (repeatable,
hex) select the rows printed, by retirement cycle and PC. The whole trace
is still processed, so the joins and totals are the same as without them;
`--limit` counts selected rows. The instructions still in flight at the
end are listed after the totals, oldest first, even when nothing retires
in the window:

```
$ coralview commits --platform core-mini-axi --pc 214 --from-cycle 600 trap-x0.fst
     605 0 00000214 00072003 lw x0, 0(x14)                                       1   -   2
root VCoreMiniAxi.core.CoreMiniAxi: 996 cycles, ... 6 in flight at the end
in flight at the end, oldest first:
  dispatched      604 pc 00000218 0007a603 lw x12, 0(x15)
  dispatched      605 pc 0000021c 00500693 addi x13, x0, 5
  dispatched      615 pc 00000144 ff010113 addi x2, x2, -16
  ...
```

### stalls: why dispatch did not advance

Block: `dispatch`. Each cycle, each of the 4 lanes gets one reason:

- **The lane dispatched or was empty.** `io_inst_N_ready`, `io_inst_N_valid`.
- **It waited behind an older lane.** Dispatch is in order.
- **It was allowed but a unit was busy.** `tryDispatch` high,
  `ready` low.
- **It was blocked by a rule.** The first failing rule in the order of
  `canDispatch`: `halted`, `interlock`, `raw`/`waw` (the instruction's
  register fields against `comb`/`regd`), `float-hazard`, `lsu-queue`,
  `rvv-queue`, `rob-full`, `trap-pending`, `csr-serialize`. `other` stands
  for the rules not reconstructed: jump, branch, fence, slot 0 and RVV
  config interlocks.

Register use is taken from the opcode, as `Decode.scala`'s `decodedInsts`
flags are.

```
$ coralview stalls --platform vme-core-mini-axi --profile 5 matrix.fst
reason           lane0   lane1   lane2   lane3
dispatched         259      82      24      17
empty              470     478     493     520
behind               0     355     517     544
halted              18       0       0       0
interlock            1       0       0       0
raw                189      72      35       3
float-hazard        87       8       0       0
lsu-queue           37      26       6       0
csr-serialize       14       2       0       0
other                9      61       9       0
lane 0 blocked, by instruction:
      pc cycles reason         instruction
00000380     28 float-hazard   feq.s x15, f14, f15
000004e0     26 raw            or x14, x14, x15
000002d4     25 float-hazard   feq.s x13, f14, f15
000001d0     24 raw            bne x11, x10, 524
00000248     24 raw            bne x13, x11, 404
```

Reading it:

- 259 + 82 + 24 + 17 = 382 instructions dispatched, the same count
  `commits` retires.
- Lane 0, which holds the oldest undispatched instruction, waited 189
  cycles on integer results and 87 on float results.
- The worst single instruction is a `feq.s` comparing the matrix test's
  float outputs: 28 cycles waiting for `f14`/`f15`.
- 406 of lane 0's 470 empty cycles are the boot sequence before the first
  instruction.

### memory: what the LSU read and wrote

Block: `lsu`. A TCM access is `io_dbus_valid` (the TCM does not
back-pressure in these builds, `"tcm_ready": false`). An external access
is `io_ebus_dbus_valid && ready`. The PC is the LSU slot's
(`io_ebus_dbus_pc`, which drives both buses). Read data is on the bus one
cycle after the request (`dbusResp = RegNext(...)` in `Lsu.scala`), which
the model joins with `Sig.pre`.

```
$ coralview memory --platform vme-core-mini-axi --manifest .../hardware-configurations.json --limit 4 matrix.fst
     432 tcm W pc 000006d0 addr 00010130 (dtcm) 4 bytes 00000000
     463 tcm W pc 000000dc addr 00010120 (dtcm) 4 bytes 0badd00d
     521 tcm W pc 000001b8 addr 00017fe0 (dtcm) 8 bytes 7fffffeefffffff0
     526 tcm R pc 000001c8 addr 00017fe0 (dtcm) 4 bytes fffffff0
root VVmeCoreMiniAxi.core.VmeCoreMiniAxi: 52 read and 53 write requests from 94 PCs, 0 faults
```

Writes show the bytes their mask enables, little-endian. Reads show the
word at the address. Region names come from the manifest's
`memory_regions`.

Each row is a **request** the bus accepted, with the data sampled where
the response would be; it does not say the access succeeded. The LSU's
faults (`io_fault_{valid,bits_write,bits_addr,bits_epc}`) are separate
rows, with the last request from the same PC in the same direction. A
fault with no request was refused before reaching a bus. The window
options of `commits` apply, by request cycle:

```
$ coralview memory --platform core-mini-axi --from-cycle 600 trap-x0.fst
     609 ext R pc 00000214 addr 30000004 4 bytes 25fb9019
     610 fault R pc 00000214 addr 30000004, requested at 609, addr 30000004
     619 tcm W pc 00000148 addr 00017fd0 4 bytes 00010120
     621 tcm W pc 0000014c addr 00017fd0 4 bytes 00000000
root VCoreMiniAxi.core.CoreMiniAxi: 15 read and 29 write requests from 24 PCs, 4 faults
```

The read at 609 returned no data: its "value" is whatever the bus held.
The store faults of the same run (`fault W pc 000001bc addr 00000100, no
request seen`) never reached a bus.

### axi: external traffic and where it comes from

Block: `axi_master`. Everything the core reads or writes outside its TCMs
leaves through one AXI4 master port (`CoreAxi.io_axi_master`). The
description names the masters behind it by AXI ID: the LSU's external
bus (`DBus2Axi`, ID 0) carries scalar, vector and tile loads and stores,
and instruction fetches outside the ITCM (`IBus2Axi`, ID 1) are
line-aligned reads. There is no DMA in these configurations.

A transaction runs from the address handshake to its last read beat or
its write response. Several can be outstanding. Read data and write
responses go to the oldest outstanding transaction of their ID; write
data, which has no ID, goes to write addresses in the order they were
accepted, and may come first. A response with nothing outstanding is
reported as unmatched.

Each transaction is pinned to its originator. The master's own request
(`io_ebus_dbus_*`, `io_ibus_*`) must be valid at the address handshake,
and its address, rounded to the description's `align`, must be the AXI
address. Its start is when that request began. For the LSU the
description also gives its in-order operation queue: an instruction
enters at dispatch (`io_req_N`) and leaves for the slot
(`slot.io_uop`), which then makes all of its requests. Following that
queue pins a request to one dynamic instance of its instruction, with
its dispatch and the slot issue. Its retirement then comes from the
`commits` model. Stores retire before the LSU writes them, so retirement
alone cannot pin them.

```
$ coralview axi --platform vme-core-mini-axi --manifest .../hardware-configurations.json --pc 270 --limit 3 vme_external_matmul.fst
   start   accept     done dir  id source addr                 bytes beats B/cycle out  origin
   29892    29893    29894 R     0 lsu    20000a90 (testbench-ram)    16  1x16    5.33   1  pc 00000270 vtle32 x23, 0(x11) (dispatched 29890, op 29891, retired 29916)
   29896    29897    29898 R     0 lsu    20000aa0 (testbench-ram)    16  1x16    5.33   1  pc 00000270 vtle32 x23, 0(x11) (dispatched 29890, op 29891, retired 29916)
   29900    29901    29902 R     0 lsu    20000ab0 (testbench-ram)    16  1x16    5.33   1  pc 00000270 vtle32 x23, 0(x11) (dispatched 29890, op 29891, retired 29916)
root VVmeCoreMiniAxi.core.VmeCoreMiniAxi: reads 1596 (14280 bytes), writes 1220 (7248 bytes) in 52711 cycles, unmatched 0
  latency, address accepted to done, min/mean/max: reads 1/1.0/1, writes 2/2.0/2 cycles
  throughput 0.417 bytes/cycle over cycles 757-52398, 3.142 while a transaction is outstanding (6852 cycles)
  outstanding at once: max 1 (reads 1, writes 1); cycles by count: 0:44789 1:6852
  source lsu (id 0): transactions 2816, bytes 21528, pinned to a request 2816, to an instruction instance 2816
```

Columns:
- `start`: when the originator's request began.
- `accept` and `done`: the AXI handshakes.
- `bytes`: read beats times the beat size, or for writes the strobed
  bytes. `beats` is beats × bytes per beat.
- `B/cycle`: bytes over the cycles from `start` to `done`.
- `out`: the transactions outstanding when this one was accepted,
  itself included.

`--profile N` adds the instructions with the most external bytes. The
filters of `commits` apply: `--from-cycle`/`--to-cycle` by acceptance and
`--pc` by originating instruction.

The numbers above describe these builds, not Coral in general. The
standalone testbench RAM answers in one cycle. `DBus2Axi` holds one
transaction at a time. Only a fetch from external memory can overlap a
data access. So the observed maximum of one outstanding transaction comes
from the bridge, not the model. `test/axi.t` covers overlapping,
out-of-order IDs, early write data and unmatched responses.

### dma: what the DMA engine moved

Block: `dma`, in the full-subsystem configurations. The engine
(`bus.DmaEngine`) has two TileLink-UL ports, and the model follows a job
across both. Requests and responses are matched by source ID.

1. **Activation.** On the CSR port, software writes `DESC_ADDR` (0x08)
   and then `CTRL` (0x00) with enable and start (bits 0 and 1). The
   description's requester, the core LSU's external bus, names the
   instruction that wrote `CTRL`.
2. **Descriptor.** On the host port, the engine reads the descriptor in
   two 16-byte halves. The first has source, destination, length, beat
   width, the fixed-address flags and `next_desc`. The second has the
   optional poll address, mask and value.
3. **Beats.** If the descriptor polls, the engine reads the word until
   it matches. It then copies one beat at a time: a read, then a write,
   each waiting for its response. With `next_desc` it fetches the next
   descriptor.
4. **Completion.** A job ends with the last write's response, or with an
   error. Software sees the end when a `STATUS` read (0x04) returns done.

```
$ coralview dma --platform subsystem-vector-normal --manifest .../hardware-configurations.json --beats 2 sim.fst
job 1: started 4855 by pc 000008ec, descriptor 20006000
  descriptor 20006000 fetched 4859-4864: 20004000 (sram) -> 00010040 (dtcm), 64 bytes in 4-byte beats
  beats 16, cycles 4868-5088, one every 14.0 cycles: latency, request accepted to response, min/mean/max reads 1/1.0/1, writes 6/6.0/6; 0.290 bytes/cycle
        4868 read 20004000 4 bytes, response 4869; write 00010040 accepted 4872, response 4878
        4882 read 20004004 4 bytes, response 4883; write 00010044 accepted 4886, response 4892
  finished 5088: 64 bytes, 234 cycles from start, 0.274 bytes/cycle
  software saw done at 5093 by pc 0000090c, 238 cycles after the start, 16 STATUS reads
...
root TOP.chip_verilator.i_coralnpu_soc.i_chisel_subsystem: jobs 3, 192 bytes in 119402 cycles, host port at most 1 outstanding, 0 stray
```

On this run, from `subsystem_dma.elf`:
- SRAM answers in one cycle.
- A TCM access goes through the core's AXI slave port and takes six to
  nine.
- One beat every 14 cycles comes to about 0.27 bytes per cycle with
  4-byte beats.

Port activity outside the sequence is printed as `stray`: a beat with no
job, a write with no read before it, or a descriptor read at the wrong
address. `test/dma.t` covers chained descriptors, polling and a stray
write.

### tiles: what the matrix engine computed

Block: `vme`. The ports are SystemVerilog packed arrays
`[NUM_BLK][NUM_BLKPORT][…]`. Element `[b][p]` is at bit offset
`(b × 4 + p) × width`. Widths and counts come from the description and must
match the trace exactly. A port writes when its byte enables are non-zero:

- If they equal the PE array's (`peWriteEn`), the write is a matrix
  result, tagged with that block's `peWritePc`.
- Otherwise it is a tile load from memory.

The model also keeps the tile register file as written.

```
$ coralview tiles --platform vme-core-mini-axi matrix.fst
     494 blk0 port0 load        tile  0 sub  0 mask ffff 00000000000000000000000000000000
     515 blk0 port0 pc 000001b0 tile  0 sub  0 mask ffff 0000001400000012ffffffeefffffff0
     557 blk0 port0 pc 000001f8 tile  0 sub  0 mask ffff 0000002800000024ffffffdcffffffe0
     ...
root VVmeCoreMiniAxi.core.VmeCoreMiniAxi: 9 sub-tile writes; 1 of 256 sub-tiles written
```

The models agree with each other on this trace:

- The tile written by `pc 1b0` in cycle 515 holds `0x14, 0x12, -0x12,
  -0x10`.
- `memory` shows the same 16 bytes stored to `0x17fe0` by `pc 1b8`/`1c4`
  in cycles 521 and 524.
- The vector stores at those PCs are also the costliest instructions in
  the `commits` profile.

### ops: vector operations per cycle

Blocks: `v_dispatch` and `dispatch_debug`. The RVV backend's dispatch
stage takes up to three uops a cycle. Each is a `UOP_QUEUE_t`
(`rvv_backend.svh`), which the description lays out field by field: 177
bits on the RVV core (`TB_SUPPORT`, `ZVE32F_ON`), 201 on the VME core,
whose `ZVT_ON` adds `altfmt`, `mtwiden`, `tm` and `tk` to `vector_csr` and
`mt_valid`/`mt_eew` to the uop. `vector_csr` is flattened into `csr_*`
fields; `units` names the `EXE_UNIT_e` values, which `ZVT_ON` extends
with `vme` and `vmelsu`.

An instruction counts when its first uop is taken, as `vl - vstart`
elements, masked or not. Its kind comes from Rivet, which decodes the word
the scalar core dispatched at the uop's PC:

- Fused multiply-adds (`vfmacc`, `vfwmacc`, `vmacc`, …) are two operations
  an element; other arithmetic, one.
- A Zvt tile multiply (`vtfmm`, `vtmmu`, `vtmms`) is `tm × vl × tk`
  multiply-accumulates, two operations each, with `tm` and `tk` from its
  uop.
- Moves (`vmv*`, `vfmv*`, `vmerge`, `vtmv`, `vtzero`, the permute unit),
  loads and stores (including tile loads and stores), and `vset*`/`mset*`
  are none.
- A uop whose PC the scalar core never dispatched is `undecoded`.

Compute instructions closer than `--gap` cycles (256) form a burst. The
rates are the operations over the whole trace, over the bursts' cycles,
and the busiest `--peak-window` cycles (64). On `rvv_matmul_fp32.elf`,
whose nine cases are 53,004 multiply-accumulates in all, the FMA unit's
elements are exactly 53,004 and its operations 106,008:

```
$ coralview ops --platform rvv-core-mini-highmem-axi --profile 3 rvv_matmul_fp32.fst
root VRvvCoreMiniHighmemAxi.core.RvvCoreMiniHighmemAxi: 1332017 cycles, 4707 vector instructions dispatched (0 not decoded)
  unit   instructions     elements          ops
  alu             104         2957            0
  fma            2334        53004       106008
  lsu            2269        50756            0
106008 ops (106008 floating point) in 9 bursts over 73201 cycles (5.5% of the trace)
ops/cycle: 0.080 over the trace, 1.448 in bursts, peak 4.000 over 64 cycles to cycle 55127
bursts:
       first       last   cycles   instrs        ops ops/cycle
        9959      10191      233        8        512     2.197
     ...
operations by instruction:
      pc  count        ops   elements  instruction
00000538    649      41536      20768  vfmacc.vf
0000052c    649      41536      20768  vfmacc.vf
00000708    155       9920       4960  vfmacc.vf
```

The `alu` instructions are the accumulators' `vmv.v.i` and `vmv8r.v`
zeroing and copies. On the VME core, `vme_external_matmul.elf` (two
19 × 23 × 5 cases) gives 8,740 operations from its `vtfmm.tvv`, exactly
2 × 2 × 2,185, and its full 16 × 16 tiles sustain 15.1 operations a cycle
over a 169-cycle burst. `coralview run --model ops --perfetto FILE` draws the
bursts, each instruction on its unit's track, and the operations of each
peak window as a counter. `test/ops.t` covers the counting, bursts and peak on a
synthetic trace.

### registers: the register files, related

Blocks: `x_registers`, `f_registers`, with `regfile_writeback`,
`float_writeback`, `dispatch_debug` and `retirement_debug`. The model
keeps each register file as `hwfrp` `State` stores, so every register is
visible at every cycle, and checks how they relate:

| Store | Built from |
|---|---|
| storage | the register file's own registers: `regfile_1..31`, and `fregfile_N` as `{sign, exponent, mantissa}` |
| written | replay of the writeback ports |
| scoreboard | replay of the dispatch-time marks (`io_debug_*_writeAddr`), writebacks and `io_pipelineFlush`, after the RTL's `(scoreboard & ~clr) \| set` and its flush rule |
| architectural | replay of the retirements from `commits` |

| Relation | Holds when |
|---|---|
| `registers.storage` | storage equals the last value written back, one sample after the write, when the clock edge has stored it |
| `registers.scoreboard`, `registers.flushed` | the traced `scoreboard` and `flushed_scoreboard` equal the replayed bits, one sample later |
| `registers.architectural` | storage equals the retired value for every register whose scoreboard bit is clear and that has no value written but not yet retired |

```
$ coralview registers --platform vme-core-mini-axi --at 600 matrix.fst
registers.storage               202 comparisons, 0 failures
registers.scoreboard            510 comparisons, 0 failures
registers.flushed               510 comparisons, 0 failures
registers.architectural         215 comparisons, 0 failures
0 pipeline flushes
storage at cycle 586:
  x1   000000f4  x2   00017fe0  x3   000108d0  x4   00000000  x5   00010120  x6   00000000
  ...
storage at the end:
  ...
  f11  00000000  f12  00000000  f13  00000000  f14  41a00000  f15  41a00000  f16  00000000
```

**Events.** The model is also a data source (`--format jsonl`):

- `registers.write`: a change of the register file's own storage, `{cycle,
  reg, value}` with `reg` the unified register (`x1` is 1, `f0` is 32). The
  first sample has one for every register, so the initial state is in the
  stream. An f register's value is its sign, exponent and mantissa as one
  32-bit number.
- `registers.flush`: a sample with a pipeline flush, `{cycle, file}` with
  `file` `x` or `f`.
- `registers.checks`: once, at the end, `{cycle, relations}`: for each
  relation the comparisons made and the failures over the whole trace. The
  comparisons are made at every sample but only counted here, so a
  consumer has them once the trace has ended.

The failures themselves are `diag` lines, and the architectural values are
the retirements of `commits`: the stream does not repeat them. In OCaml,
`Registers.Accumulator` rebuilds the storage, the flushes and the counts
from the events.

What the results show:

- **All relations hold** on traces from all six simulated configurations,
  including a 2-million-cycle highmem run.
- **The checks bite.** Four deliberate mistakes each made exactly their
  relation fail (22 to 144 failures): drop either one-sample lag, drop the
  pending guard, or apply `set` before `clr`.
- **Flushes are covered only by a fixture.** None of the example programs
  flushes the pipeline; `test/registers.t` flushes once, with nothing
  pending, so the flush rule has not been exercised on a real trace.
- **`--at` prints the storage** as of the last change at or before the
  given cycle. Snapshots are persistent, so every past state is kept.
- **Exit status.** The command exits 1 when a relation fails, and `make
  smoke` runs it on every CI leg.

### vectors: the vector register file, related

Blocks: `v_registers`, with the `commits` blocks. The description gives
the layout of the write ports' `RT2VRF_t` structs, most significant field
first, because the trace has them only as flat vectors and their layout
depends on build defines (`TB_SUPPORT` adds `uop_pc`):

```json
"v_registers": {
  "scope": ["core", "rvvCore", "rvvCoreWrapper", "core", "backend", "u_vrf"],
  "base": 64, "count": 32, "vlen": 128,
  "storage": "vrf_rd_data_full",
  "writes": {
    "ports": 4, "valid": "rt2vrf_wr_valid", "data": "rt2vrf_wr_data",
    "layout": [
      { "name": "uop_pc", "width": 32 }, { "name": "rt_index", "width": 5 },
      { "name": "rt_data", "width": 128 }, { "name": "rt_strobe", "width": 16 }
    ]
  }
}
```

| Store | Built from |
|---|---|
| storage | `vrf_rd_data_full`, 32 registers of `vlen` bits |
| written | replay of the write ports byte by byte under `rt_strobe`; writes to one register in one cycle are ORed, as `rvv_backend_vrf.sv` merges them |
| last writer | the cycle and `uop_pc`s of each register's last write |

| Relation | Holds when |
|---|---|
| `vectors.storage` | every byte written so far holds its last written value one sample later; bytes never written are not compared, so no reset value is assumed |
| `vectors.retired` | a vector instruction that `commits` sees retire with a `v` destination was the last to write that register before the retirement's cycle |

```
$ coralview vectors --platform rvv-core-mini-axi --limit 3 rvv.fst
     599 port0 pc 0000025c v1  strobe ffff fffffffcfffffffbfffffffafffffff9
     603 port0 pc 00000260 v2  strobe ffff 00000009000000060000000300000000
     607 port0 pc 0000026c v1  strobe ffff 0000000500000001fffffffdfffffff9
root VRvvCoreMiniAxi.core.RvvCoreMiniAxi: 1012 cycles, 13 vector register writes from 4 PCs
  pc 0000025c: 4 writes to v1, cycles 599-656
  pc 00000260: 4 writes to v2, cycles 603-660
  pc 0000026c: 4 writes to v1, cycles 607-664
  pc 00000354: 1 writes to v1, cycles 760-760
vectors.storage                  13 comparisons, 0 failures
vectors.retired                  13 comparisons, 0 failures
storage at the end:
  v0   00000000000000000000000000000000
  v1   000a535341505f5656525f4c41524f43
  ...
```

What the results show:

- **Vector results have values and PCs.** `commits` shows `v1=?` because
  the mini cores zero the retirement buffer's data; the write ports carry
  the value and, with `TB_SUPPORT`, the PC. Each vector instruction in the
  example programs retires from the scalar core exactly one cycle after
  its write.
- **Both relations hold** on the RVV and VME traces (`rvv.elf`,
  `rvv_fp.elf`, `rvv_tcm512k.elf`, `matrix.elf`; 10 to 13 writes each).
- **The checks bite.** Shifting the `rt_data` field or the register index
  fails `vectors.storage`; the index also fails `vectors.retired`; dropping
  either one-sample lag fails its relation. The synthetic trace in
  `test/vectors.t` covers what the example programs do not: partial byte
  enables, two ports writing one register in a cycle, and a write in the
  cycle another instruction retires the same register.
- **Limits.** Every example write enables all 16 bytes and writes one
  register per instruction, so masked writes and register groups
  (`LMUL > 1`) are covered only by the synthetic trace.

### traps: faults and whether they were delivered

Blocks: `traps`, with `dispatch_debug` and `retirement_debug`. The block
names the fault manager's output (`io_out_valid` with the `mcause`,
`mepc` and `mtval` it sends to the CSRs), the inputs that say where a
fault came from (`io_in_memory_fault_*`, `io_in_fetchFault_valid`,
`io_out_bits_decode`, and `io_in_rvv_fault_valid` on the RVV cores), and
the CSR registers `mcause`, `mepc`, `mtval` and `mtvec`.

For each fault it reports three observations, kept apart because each
can happen without the next:

| Observation | From |
|---|---|
| fault asserted | the fault manager's output, with its source: `load`, `store`, `fetch`, `rvv`, `decode` |
| CSRs updated | the first later cycle in which `mcause`, `mepc` and `mtval` hold the fault's values |
| trap delivered | the first retirement of the handler's first instruction (`mtvec` with the mode bits cleared) |

It also shows when the faulting PC retired, before and after the fault,
and whether as a trap row. CSR changes that match no fault, such as the
handler writing `mepc`, are listed as such and are not faults. A fault's
record ends at the next fault or at the end of the trace. These are
observations, not relations: the command does not fail on them.

```
$ coralview traps --platform core-mini-axi trap-x0.fst
     416 store fault: cause 7 (store access fault), pc 000001bc, mtval 00000100
         csr      mcause/mepc/mtval hold them at 417
         pc       retired up to the fault never, after it at 417 as a trap
         handler  00000144 dispatched at 421, retired at 422: delivered
     456 csr change with no fault: mcause 7 (store access fault), mepc 000001c0, mtval 00000100
...
     610 load fault: cause 5 (load access fault), pc 00000214, mtval 30000004
         csr      mcause/mepc/mtval hold them at 611
         pc       retired up to the fault at 605, after it never
         handler  00000144 dispatched at 615, retired never: not delivered by cycle 995
root VCoreMiniAxi.core.CoreMiniAxi: 996 cycles, 4 faults, 3 delivered
```

What the results show:

- **Store faults** (`trap_address.elf`): cause 7 with the full byte
  address; the store retires as a trap the next cycle and the handler
  retires five cycles after the fault.
- **A load into x0** at `0x214` retires at cycle 605, before its fault at
  610. The CSRs take the fault's values and the handler is dispatched,
  but it never retires: the CSR update alone is not a delivered trap.
- **An illegal RVV instruction** on the scalar core (`0x0c007857` at
  `0x510`) is a `decode` fault with cause 2, and the default handler at
  `0x410` retires.
- **`scalar.elf` on the highmem core** never halts because it loops on a
  store access fault: `sw x0, 0(x10)` at `0x430` to `0x1013`, with `mtvec`
  still 0, so each delivery restarts the program. That is 64,504 faults
  in 2 million cycles. The ELF is linked for the default memory map.
- The example programs on the other configurations take no faults.

## Any signal, over a window

`signals` prints named signals without a model, for evidence the models
do not cover. Paths are absolute and separated by `/`, as `coralview tree`
prints them, so dotted scope names such as `VCoreMiniAxi.core` stay
whole. A path the trace lacks is an error (exit 3), not an omission.

- **Sampled** (`--platform P`): once per cycle, by the platform's clock and
  sample rule, which the first line names. `--from-cycle`/`--to-cycle`
  select a window; the run stops after it.
- **Raw** (`--raw`): every value change at its trace timestamp, with no
  clock. `--from-time`/`--to-time` select timestamps; cycle options are
  rejected, as timestamps are not cycles (the testbench dumps both
  edges).
- `--changes` keeps only values that changed; the window's first sample
  shows every value. `--format jsonl` (or `--json`) prints one record
  per value, with a `type`, between a header and a summary. Unknown bits
  are kept: a value with any is printed in binary, with `x`.

```
$ c=VCoreMiniAxi.core/CoreMiniAxi/core/score/csr
$ coralview signals --platform core-mini-axi --changes --from-cycle 600 trap-x0.fst $c/mcause $c/mtval $c/io_bru_out_mepc
# sampled after_falling on io_aclk at VCoreMiniAxi.core.CoreMiniAxi
     600       1202   32 VCoreMiniAxi.core/CoreMiniAxi/core/score/csr/mcause 0x00000007
     600       1202   32 VCoreMiniAxi.core/CoreMiniAxi/core/score/csr/mtval 0x00001238
     600       1202   32 VCoreMiniAxi.core/CoreMiniAxi/core/score/csr/io_bru_out_mepc 0x000001fc
     611       1224   32 VCoreMiniAxi.core/CoreMiniAxi/core/score/csr/mcause 0x00000005
     611       1224   32 VCoreMiniAxi.core/CoreMiniAxi/core/score/csr/mtval 0x30000004
     611       1224   32 VCoreMiniAxi.core/CoreMiniAxi/core/score/csr/io_bru_out_mepc 0x00000214
```

## Output formats

Every analysis command (`commits`, `stalls`, `memory`, `axi`, `dma`,
`tiles`, `registers`, `vectors`, `traps`) and `check` and `signals` take:

- `--format text` (the default): the tables shown in this document;
- `--format jsonl`: JSON Lines, one object per line, each with a `type`:
  - a header, `{"type":"coralview","schema_version":1,"model":…,"platform":…,"trace":…}`;
  - the analysis' events, in the order it produces them, as
    `<model>.<record>` (`axi.transaction`, `stalls.span`, …), selected by
    `--from-cycle`, `--to-cycle`, `--pc` and `--limit` as the text rows are;
  - the diagnostics, as `diag` lines (relation failures, unknown bits);
  - the summary, `<model>.summary`, which always covers the whole trace;
- `--output FILE` (`-o`): write to a file instead of the standard output.

Numbers are JSON numbers: addresses too, so `jq` can compare them.
Members that have no value (a transaction not done, a region with no
manifest) are left out. A run's events can be read back:

- `coralview render FILE.jsonl` prints the text the command prints, with
  the same options (`--profile`, `--limit`, `--manifest`, …);
- `coralview profile [-n N] FILE.jsonl` prints the profile of `commits`,
  `stalls` or `axi` without the trace.

A platform that is not built in is given again with `--platform`.

### Several analyses in one pass

`coralview run` builds the analyses named by `--model M` or
`--sink M:KIND:PATH` in one net and reads the trace once; each gets the
text, or JSONL, its own command gives (`KIND` is `text` or `jsonl`,
`PATH` `-` for the standard output). Analyses that depend on another
(`axi` on `commits`) share it. On `matrix.elf` all eight core analyses take
1.8 s together, against about 10 s for each alone, as opening the trace
dominates. The common options (`--manifest`, `--profile`, `--at`,
`--beats`, the window) apply to every analysis they concern.

Three views come only from `run`:

- `--perfetto FILE`: a Chrome trace for ui.perfetto.dev, a process per
  analysis: a track per AXI ID with a slice per transaction and the
  outstanding count, the DMA jobs, descriptor fetches and host beats, and
  a track per dispatch lane with its stall spans (`stalls`). Time is in
  cycles. Perfetto's trace processor loads the VME external trace's
  166,770 slices.
- `--kanata FILE`: a Kanata log for Konata: each retired instruction from
  its dispatch to its retirement, with the stall that kept it from
  dispatching in lane 1. It needs `commits`, and uses `stalls` where the
  platform has a `dispatch` block.
- `--report FILE`: Markdown with the platform, trace and cycles, then each
  analysis' summary and profile, without its rows.

```
$ coralview run --platform vme-core-mini-axi --model axi --model stalls --perfetto vme.json --report vme.md vme_external_matmul.fst
```

### Reading the events from OCaml

The `coralview` library exports the events and their codecs, so a program
need not run the CLI or parse the lines itself:

- `Output.OUTPUT` is the part of an analysis a consumer needs (`name`,
  `Event.t`, `Event.jsont`); every analysis module satisfies it.
  `Output.decode_event (module Axi)` turns one line into an `Axi.Event.t`,
  or an `Error` for malformed JSON, a wrong tag or a field of the wrong
  type; `decode_events` maps a sequence of lines and `encode_event` goes
  the other way.
- `Jsonl.reader (module Axi) lines` reads a saved file: its `events` are
  `Ok event` or `Error message` per line (reading goes on after an error),
  and the header, diagnostics and error messages are kept apart. The
  diagnostics follow the events in a file, so call `finish` before
  trusting `diags ()`. Only the analysis' own `<name>.summary` line is
  skipped; a header is not required.
- `Analysis.stream (module Axi) config platform trace`, or `events_file`
  on a path (FST or VCD), gives the same `Axi.Event.t` from a waveform,
  with the diagnostics and a `finish` that runs the trace to its end
  without keeping the events nobody read.
- `Accumulator.ACCUMULATOR` keeps totals of the events as they arrive:
  `add` an event, take a `snapshot` at any time, and `tap` adds the
  events of a sequence as it is pulled. `Memory`, `Tiles`, `Stalls`, `Axi` and
  `Registers` have one; a snapshot holds only what the events carry. `Memory` and
  `Tiles` rebuild their whole summary. `Stalls` counts the cycles of closed
  spans and lists the open ones with their start. `Axi` leaves out what is
  the model's state: the cycles of the trace, outstanding counts,
  resynchronizations and the PC words. Accumulating a filtered stream
  gives the totals of that stream, not of the trace; do not add a saved
  summary to them.

### The JSONL contract

For a program that reads the lines without the library:

- One JSON object per line, with a `type` member. The header comes first;
  the events follow in the order the analysis produced them, then the
  diagnostics, then the summary. A reader should accept diagnostics
  anywhere and a file with no header or summary.
- `schema_version` is 1. It is there for readers to check; coralview does
  not enforce it yet.
- Integers are JSON numbers: cycles, addresses and PCs. A `cycle` counts
  the samples of the platform's clock; a `time` is the trace's timestamp.
- `span` is `{"start", "stop"}` in cycles, both included; `stop` is left
  out for a span still open when the trace ended.
- `data` is hex, most significant digit first, four bits a digit, so its
  width is `4 × length`. Unknown bits in the trace are reported by a `diag`
  line and read as 0 in an event; `signals` keeps them, in binary with `x`.
- A member with no value is left out, never `null`.
- An event of a stream cut by `--from-cycle`, `--to-cycle`, `--pc` or
  `--limit` is still the same record; only the summary covers the whole
  trace.

### JSONL schema

The members of each record type, as dotted paths (`[]` for the elements
of an array), as the analyses write them on the test fixtures
(`tools/jsonl-schema.sh`; `test/doc.t` checks this list). Optional members
appear only when set.

<!-- schema -->
```
axi.summary: cycles first incomplete last max_reads max_writes occupancy[] read_bytes read_latency.max read_latency.min read_latency.n read_latency.sum reads resyncs sources[].bytes sources[].disagreeing sources[].id sources[].instances sources[].pinned sources[].source sources[].transactions unmatched words[].pc words[].word write_bytes write_latency.max write_latency.min write_latency.n write_latency.sum writes
axi.transaction: beat_bytes burst origin.agrees origin.instance.dispatched origin.instance.issued origin.instance.pc origin.instance.retired origin.instance.word origin.issued origin.request origin.write source transaction.accepted transaction.address transaction.beats transaction.bytes transaction.completed transaction.first_data transaction.id transaction.outstanding transaction.requested transaction.status transaction.write
axi.unmatched: cycle id what write
check.binding: actual model path purpose root status width
check.summary: bound failed
commits.commit: charged dest.reg dest.value instance.dispatched instance.pc instance.retired instance.word lane store trap written
commits.summary: before cycles empty in_flight missing_values skipped unmatched_retires
coralview: model platform schema_version trace
diag: code cycle message paths[] severity source time
dma.job: aborted beats[].read.accepted beats[].read.address beats[].read.beats beats[].read.bytes beats[].read.completed beats[].read.first_data beats[].read.id beats[].read.outstanding beats[].read.requested beats[].read.status beats[].read.write beats[].write.accepted beats[].write.address beats[].write.beats beats[].write.bytes beats[].write.completed beats[].write.first_data beats[].write.id beats[].write.outstanding beats[].write.requested beats[].write.status beats[].write.write descriptors[].at descriptors[].beat descriptors[].dst.address descriptors[].dst.bytes descriptors[].dst.write descriptors[].dst_fixed descriptors[].fetch.start descriptors[].fetch.stop descriptors[].len descriptors[].next descriptors[].poll.address descriptors[].poll.mask descriptors[].poll.value descriptors[].src.address descriptors[].src.bytes descriptors[].src.write descriptors[].src_fixed error first observed.cycle observed.pc pc polls span.start span.stop status_reads
dma.stray: cycle what
dma.summary: bytes cycles jobs max_outstanding stray
memory.access: access.address access.bytes access.write bus cycle data lanes[] pc
memory.fault: address cycle pc request.address request.cycle write
memory.summary: faults pcs reads writes
ops.burst: first flops instructions last ops
ops.op: cycle elements float kind lmul mnemonic ops pc sew unit vl vstart
ops.summary: bursts busy cycles flops instructions ops peak.last peak.ops peak.window undecoded units[].elements units[].instructions units[].ops units[].unit
registers.checks: cycle relations[].code relations[].comparisons relations[].failures
registers.flush: cycle file
registers.summary: architectural[].reg architectural[].value cycles flushes relations[].code relations[].comparisons relations[].failures storage[].reg storage[].value
registers.write: cycle reg value
signals.sample: cycle path phase time value width
signals.summary: samples
stalls.span: lane pc reason span.start span.stop word
stalls.summary: counts[].cycles counts[].lane counts[].reason cycles
tiles.summary: file[].data file[].sub file[].tile writes
tiles.write: block cycle data mask pc port sub tile
traps.csr_change: cycle mcause mepc mtval
traps.fault: cause csr cycle delivered dispatched handler pc retired_after.at retired_after.trapped retired_before.at retired_before.trapped source until value
traps.summary: cycles delivered faults unmatched
vectors.summary: cycles failures[].code failures[].cycle failures[].message failures[].severity failures[].source failures[].time failures[].type relations[].code relations[].comparisons relations[].failures storage[].reg storage[].value
vectors.write: cycle data pc port reg strobe
```
<!-- end schema -->

## Execution time of each instruction

An FST capture gives cycle-exact timing for every instruction, as far as
the probed stages go. The `commits` model reports three numbers per
instruction:

| Column | Meaning | From |
|---|---|---|
| `d->r` | dispatch to retirement: the instruction's latency through execution and the retirement buffer | dispatch lane `instFire` and retirement lane `valid` cycles |
| `d->w` | dispatch to the register writeback that produced its result | `regfile`/`float` `writeData` cycles |
| `charged` | cycles during which it was the oldest instruction in flight | one charge per cycle to the head of the dispatch-order queue |

`d->r` is latency. Instructions overlap, so latencies do not add up to run
time. `charged` is the run-time view: summed over all instructions, plus
the cycles before the first dispatch and the cycles with nothing in flight,
it equals the cycle count. Sorted by PC (`--profile N`), it says which
instructions the run was waiting for. Add `stalls` to see why the next
instruction could not dispatch while they were in flight.

On `matrix.elf`:

- the VME core spends 406 of 1,084 cycles in boot;
- of the remaining cycles, the vector stores of matrix results
  (`0x52c17027`, 21–27 cycles each) and the `lw`/`beq` loop that checks
  them take the largest shares.

Not yet timed:

- the fetch-to-dispatch wait (fetch buffer occupancy);
- the issue-to-unit and unit-internal stages;
- the vector backend's uops.

These need the fetch and execution-unit blocks and the RVV backend layouts
(next section).

## Not observed yet

- **Fetch** (`core.score.fetch`: fetcher, instruction buffer, branch
  redirects): the front end's share of `empty` cycles.
- **Execution units** (`alu_N`, `bru_N`, `mlu`, `dvu`, `floatCore`): issue
  to completion per unit.
- **RVV backend** (`u_command_queue` … `u_rob`, `u_retire`; 144k
  variables): beyond the dispatch `ops` binds, the issue to each unit and
  reservation-station occupancy. These need more struct layouts, as
  `vectors` and `ops` carry.
- **VME reads.** The tile register file's reads are combinational, with no
  enable at its ports. Which operands each instruction read needs the PE
  array's handshake (`zvtPeArray`).
- **AXI slave** (writes into the TCMs from outside, such as the DMA's),
  **other CSRs, debug module.**
- **The subsystem's other bus masters** (the SPI bridge, the ISP ports)
  and the crossbar between them.

Each would be a new block in the platform descriptions and a model that
binds it. The descriptions would say which configurations have the block
and under which names.
