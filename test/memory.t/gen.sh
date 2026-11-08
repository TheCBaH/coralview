#!/bin/bash
# Writes memory.vcd to stdout: a clock, the LSU's TileLink-UL port (channel A and D), its fault port, and the PC of
# its slot, set at each falling edge.
vars=(
  "1 av io_tlul_a_valid" "1 ar io_tlul_a_ready" "3 ao io_tlul_a_bits_opcode" "4 az io_tlul_a_bits_size"
  "6 as io_tlul_a_bits_source" "32 aa io_tlul_a_bits_address" "16 am io_tlul_a_bits_mask"
  "128 ad io_tlul_a_bits_data"
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
echo '$scope module lsu $end'
for v in "${vars[@]}"; do set -- $v; width[$2]=$1; echo "\$var wire $1 $2 $3 \$end"; done
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
for v in "${vars[@]}" "32 ep"; do set -- $v; echo "b0 $2"; done
echo '$end'
# cycle: "id hex" ... (values hold until changed); x for unknown
cycles=(
  "av 1 ar 1 ao 1 az 2 as 0 aa 10004 am 00f0 ad 00000000000000000000deadbeef00000000 ep 100"
  "ao 4 az 2 as 1 aa 10008 am 0f00 ad 0 ep 104 dv 1 ds 0"
  "av 0 dv 1 ds 1 dd 00000000112233440000000000000000"
  "av 1 ao 1 as 2 aa 20000000 am 000f ad cafef00d ep 108 dv 0"
  "ao 4 as 3 aa 20000010 am 000f ad 0 ep 10c"
  "av 0 fv 1 fa 30000000 fe 10c dv 1 ds 2"
  "fw 1 fa 40 fe 110 ds 3 dd 00000000000000000000000055667788"
  "fv 0 fw 0 av 1 as 4 aa 20000020 ep 114 dv 0"
  "av 0"
  "dv 1 ds 4 dd x"
  "dv 0"
)
t=0
for c in "${cycles[@]}" ""; do
  echo "#$((t + 1))"
  echo 1ck
  echo "#$((t + 2))"
  echo 0ck
  set -- $c
  while [ $# -gt 0 ]; do
    if [ "$2" = x ]; then echo "bx $1"; else echo "$(bin ${width[$1]} $2) $1"; fi
    shift 2
  done
  t=$((t + 2))
done
