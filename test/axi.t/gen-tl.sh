#!/bin/bash
# Writes axi-tl.vcd to stdout: a core with one dispatch and one retirement lane, its AXI master port, and the
# TileLink-UL ports of the LSU and of fetch, whose requests reach the AXI port some cycles after their acceptance.
declare -A width
vars=(
  "1 ck io_aclk"
  "1 df io_debug_dispatch_0_instFire" "32 da io_debug_dispatch_0_instAddr" "32 di io_debug_dispatch_0_instInst"
  "1 tv io_debug_rb_inst_0_valid" "32 tp io_debug_rb_inst_0_bits_pc" "7 tx io_debug_rb_inst_0_bits_idx"
  "1 tt io_debug_rb_inst_0_bits_trap"
  "1 gv io_debug_regfile_writeData_0_valid" "5 ga io_debug_regfile_writeData_0_bits_addr"
  "32 gd io_debug_regfile_writeData_0_bits_data"
  "1 fv io_tlul_fetch_a_valid" "1 fr io_tlul_fetch_a_ready" "6 fs io_tlul_fetch_a_bits_source"
  "32 fa io_tlul_fetch_a_bits_address" "1 fd io_tlul_fetch_d_valid" "6 ft io_tlul_fetch_d_bits_source"
)
for ch in read_addr write_addr; do
  p=${ch:0:1}
  vars+=("1 ${p}v io_axi_master_${ch}_valid" "1 ${p}r io_axi_master_${ch}_ready"
    "32 ${p}a io_axi_master_${ch}_bits_addr" "6 ${p}i io_axi_master_${ch}_bits_id"
    "8 ${p}l io_axi_master_${ch}_bits_len" "3 ${p}s io_axi_master_${ch}_bits_size"
    "2 ${p}b io_axi_master_${ch}_bits_burst")
done
vars+=("1 dv io_axi_master_read_data_valid" "1 dr io_axi_master_read_data_ready"
  "6 di2 io_axi_master_read_data_bits_id" "2 dp io_axi_master_read_data_bits_resp"
  "1 dl io_axi_master_read_data_bits_last"
  "1 xv io_axi_master_write_data_valid" "1 xr io_axi_master_write_data_ready"
  "16 xs io_axi_master_write_data_bits_strb" "1 xl io_axi_master_write_data_bits_last"
  "1 bv io_axi_master_write_resp_valid" "1 br io_axi_master_write_resp_ready"
  "6 bi io_axi_master_write_resp_bits_id" "2 bp io_axi_master_write_resp_bits_resp")
lsu=("1 ev io_tlul_a_valid" "1 er io_tlul_a_ready" "3 eo io_tlul_a_bits_opcode" "6 es io_tlul_a_bits_source"
  "32 ea io_tlul_a_bits_address" "1 ed io_tlul_d_valid" "6 et io_tlul_d_bits_source"
  "1 qv io_req_0_valid" "1 qr io_req_0_ready" "32 qp io_req_0_bits_pc")
slot=("1 sv io_uop_valid" "1 sr io_uop_ready" "32 sp io_uop_bits_pc" "32 ep io_pc")
for v in "${vars[@]}" "${lsu[@]}" "${slot[@]}"; do set -- $v; width[$2]=$1; done
echo '$timescale 1ps $end'
echo '$scope module TOP $end'
echo '$scope module core $end'
for v in "${vars[@]}"; do set -- $v; echo "\$var wire $1 $2 $3 \$end"; done
echo '$scope module lsu $end'
for v in "${lsu[@]}"; do set -- $v; echo "\$var wire $1 $2 $3 \$end"; done
echo '$scope module slot $end'
for v in "${slot[@]}"; do set -- $v; echo "\$var wire $1 $2 $3 \$end"; done
echo '$upscope $end'
echo '$upscope $end'
echo '$upscope $end'
echo '$upscope $end'
echo '$enddefinitions $end'
# set ID VALUE...: scalar or vector values, in pairs.
set_() {
  while [ $# -gt 0 ]; do
    local w=${width[$1]} v=$(($2)) s=""
    if [ "$w" = 1 ]; then echo "$v$1"; else
      for ((i=w-1;i>=0;i--)); do s+=$(( (v>>i)&1 )); done; echo "b$s $1"; fi
    shift 2
  done
}
echo '#0'
echo '$dumpvars'
for v in "${vars[@]}" "${lsu[@]}" "${slot[@]}"; do set -- $v; set_ $2 0; done
set_ tx 0x7f rs 4 ws 4 rb 1 wb 1
echo '$end'
at() { echo "#$((2*$1+1))"; echo "1ck"; echo "#$((2*$1+2))"; echo "0ck"; }
dispatch() { set_ df 1 da $1 di $2 qv 1 qr 1 qp $1; }
nodispatch() { set_ df 0 qv 0 qr 0; }
issue() { set_ sv 1 sr 1 sp $1; }
noissue() { set_ sv 0 sr 0; }
retire() { set_ tv 1 tp $1; }
at 0; dispatch 0x100 0x00052503
# The load is accepted on A at 1 with source 5; the AXI read for it is accepted at 3, as ID 5.
at 1; nodispatch; issue 0x100; set_ ep 0x100 ev 1 er 1 eo 4 es 5 ea 0x20000000
# A fetch overlaps it: source 1, line-aligned, which the arbiter makes ID 32 + 1.
at 2; noissue; set_ ev 0 er 0 fv 1 fr 1 fs 1 fa 0x20001000
at 3; set_ fv 0 fr 0 rv 1 rr 1 ra 0x20000000 ri 5
at 4; set_ ra 0x20001000 ri 33 dv 1 dr 1 di2 5 dl 1
at 5; set_ rv 0 rr 0 di2 33
at 6; set_ dv 0 dr 0 dl 0 ed 1 et 5 fd 1 ft 1; retire 0x100; dispatch 0x104 0x00b52823
# A store, whose write is accepted two cycles after its request, with its data a cycle later.
at 7; set_ ed 0 fd 0 tv 0; nodispatch; issue 0x104; set_ ep 0x104 ev 1 er 1 eo 1 es 6 ea 0x20000010
at 8; noissue; set_ ev 0 er 0
at 9; set_ wv 1 wr 1 wa 0x20000010 wi 6
at 10; set_ wv 0 wr 0 xv 1 xr 1 xs 0x000f xl 1
at 11; set_ xv 0 xr 0 xl 0 bv 1 br 1 bi 6
at 12; set_ bv 0 br 0 ed 1 et 6; retire 0x104
# A request whose source nobody asked for: the debug module's, ID 16 + 2, with no request to pin to.
at 13; set_ ed 0 tv 0 rv 1 rr 1 ra 0x30000000 ri 18
at 14; set_ rv 0 rr 0 dv 1 dr 1 di2 18 dl 1
at 15; set_ dv 0 dr 0 dl 0
at 16
