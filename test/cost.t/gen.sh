#!/bin/bash
# Writes cost.vcd to stdout: the commits signals of platform.t's core.vcd and the LSU's TileLink-UL port and slot PC.
# Cycle N is set at the falling edge #(2N+2); a value holds until changed.
vars=(
  "1 df io_debug_dispatch_0_instFire" "32 da io_debug_dispatch_0_instAddr" "32 di io_debug_dispatch_0_instInst"
  "1 rv io_debug_rb_inst_0_valid" "32 rp io_debug_rb_inst_0_bits_pc" "7 ri io_debug_rb_inst_0_bits_idx"
  "1 rt io_debug_rb_inst_0_bits_trap" "1 wv io_debug_regfile_writeData_0_valid"
  "5 wa io_debug_regfile_writeData_0_bits_addr" "32 wd io_debug_regfile_writeData_0_bits_data"
)
lsu=(
  "1 av io_tlul_a_valid" "1 ar io_tlul_a_ready" "3 ao io_tlul_a_bits_opcode" "4 az io_tlul_a_bits_size"
  "6 as io_tlul_a_bits_source" "32 aa io_tlul_a_bits_address" "16 am io_tlul_a_bits_mask" "128 ad io_tlul_a_bits_data"
  "1 dv io_tlul_d_valid" "6 ds io_tlul_d_bits_source" "128 dd io_tlul_d_bits_data" "1 de io_tlul_d_bits_error"
  "1 fv io_fault_valid" "1 fw io_fault_bits_write" "32 fa io_fault_bits_addr" "32 fe io_fault_bits_epc"
)
declare -A width
bin() { # bin WIDTH HEX: the value at full width
  local w=$1 h=$2 b="" i
  for ((i = 0; i < ${#h}; i++)); do
    case ${h:i:1} in
      0) b+=0000 ;; 1) b+=0001 ;; 2) b+=0010 ;; 3) b+=0011 ;; 4) b+=0100 ;; 5) b+=0101 ;; 6) b+=0110 ;;
      7) b+=0111 ;; 8) b+=1000 ;; 9) b+=1001 ;; a) b+=1010 ;; b) b+=1011 ;; c) b+=1100 ;; d) b+=1101 ;;
      e) b+=1110 ;; f) b+=1111 ;;
    esac
  done
  while [ ${#b} -lt "$w" ]; do b=0$b; done
  echo "b${b: -$w}"
}
echo '$timescale 1ps $end'
echo '$scope module TOP $end'
echo '$scope module core $end'
echo '$var wire 1 ck io_aclk $end'
for v in "${vars[@]}"; do set -- $v; width[$2]=$1; echo "\$var wire $1 $2 $3 \$end"; done
echo '$scope module lsu $end'
for v in "${lsu[@]}"; do set -- $v; width[$2]=$1; echo "\$var wire $1 $2 $3 \$end"; done
width[ep]=32
echo '$scope module slot $end'
echo '$var wire 32 ep io_pc $end'
echo '$upscope $end'
echo '$upscope $end'
echo '$upscope $end'
echo '$upscope $end'
echo '$enddefinitions $end'
echo '#0'
echo '$dumpvars'
echo 0ck
for v in "${vars[@]}" "${lsu[@]}" "32 ep"; do set -- $v; echo "b0 $2"; done
echo '$end'
# cycle N: "id hex" ...
cycles=(
  ""
  "df 1 da 80000000 di 02a00513"
  "da 80000004 di 00a5a023"
  "df 0 wv 1 wa a wd 2a av 1 ar 1 ao 1 az 2 as 0 aa 10000 am 000f ad deadbeef ep 80000004"
  "wv 0 av 0 rv 1 rp 80000000 ri a"
  "rp 80000004 ri 7f"
  "rv 0"
)
t=0
for c in "${cycles[@]}" ""; do
  echo "#$((t + 1))"
  echo 1ck
  echo "#$((t + 2))"
  echo 0ck
  set -- $c
  while [ $# -gt 0 ]; do
    echo "$(bin ${width[$1]} $2) $1"
    shift 2
  done
  t=$((t + 2))
done
