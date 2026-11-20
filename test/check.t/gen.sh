#!/bin/bash
# Writes two.vcd to stdout: the signals of the commits and memory models, without
# io_debug_regfile_writeData_0_bits_data (commits) and io_fault_bits_epc (memory).
core=(
  "1 io_aclk" "1 io_debug_dispatch_0_instFire" "32 io_debug_dispatch_0_instAddr" "32 io_debug_dispatch_0_instInst"
  "1 io_debug_regfile_writeData_0_valid" "5 io_debug_regfile_writeData_0_bits_addr"
  "1 io_debug_rb_inst_0_valid" "32 io_debug_rb_inst_0_bits_pc" "7 io_debug_rb_inst_0_bits_idx"
  "1 io_debug_rb_inst_0_bits_trap"
)
lsu=(
  "1 io_tlul_a_valid" "1 io_tlul_a_ready" "3 io_tlul_a_bits_opcode" "4 io_tlul_a_bits_size"
  "6 io_tlul_a_bits_source" "32 io_tlul_a_bits_address" "16 io_tlul_a_bits_mask" "128 io_tlul_a_bits_data"
  "1 io_tlul_d_valid" "6 io_tlul_d_bits_source" "128 io_tlul_d_bits_data" "1 io_tlul_d_bits_error"
  "1 io_fault_valid" "1 io_fault_bits_write" "32 io_fault_bits_addr"
)
n=0
ids=()
decl() { n=$((n + 1)); ids+=("v$n"); echo "\$var wire $1 v$n $2 \$end"; }
echo '$timescale 1ps $end'
echo '$scope module TOP $end'
echo '$scope module core $end'
for v in "${core[@]}"; do decl $v; done
echo '$scope module lsu $end'
for v in "${lsu[@]}"; do decl $v; done
echo '$scope module slot $end'
decl 32 io_pc
echo '$upscope $end'
echo '$upscope $end'
echo '$upscope $end'
echo '$upscope $end'
echo '$enddefinitions $end'
echo '#0'
echo '$dumpvars'
echo 0v1
for id in "${ids[@]:1}"; do echo "b0 $id"; done
echo '$end'
echo '#1'
echo 1v1
echo '#2'
echo 0v1
