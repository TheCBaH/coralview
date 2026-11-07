#!/bin/bash
# Writes entry.vcd to stdout: the commits signals of platform.t's core.vcd: a kernel with a call inside it, then code after the kernel.
# Cycle N is set at the falling edge #(2N+2); a value holds until changed.
vars=(
  "1 df io_debug_dispatch_0_instFire" "32 da io_debug_dispatch_0_instAddr" "32 di io_debug_dispatch_0_instInst"
  "1 rv io_debug_rb_inst_0_valid" "32 rp io_debug_rb_inst_0_bits_pc" "7 ri io_debug_rb_inst_0_bits_idx"
  "1 rt io_debug_rb_inst_0_bits_trap" "1 wv io_debug_regfile_writeData_0_valid"
  "5 wa io_debug_regfile_writeData_0_bits_addr" "32 wd io_debug_regfile_writeData_0_bits_data"
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
echo '$upscope $end'
echo '$upscope $end'
echo '$enddefinitions $end'
echo '#0'
echo '$dumpvars'
echo 0ck
for v in "${vars[@]}"; do set -- $v; echo "b0 $2"; done
echo '$end'
# cycle N: "id hex" ...
cycles=(
  ""
  "df 1 da 80000000 di 00100513"
  "da 80000004 di 00200513"
  "da 80000008 di 00c000ef"
  "da 80000014 di 00300593"
  "da 80000018 di 00008067"
  "da 8000000c di 00400613"
  "da 80000010 di 00008067"
  "da 80000020 di 00500693"
  "df 0 rv 1 rp 80000000 ri a"
  "rp 80000004 ri a"
  "rp 80000008 ri 1"
  "rp 80000014 ri b"
  "rp 80000018 ri 7f"
  "rp 8000000c ri c"
  "rp 80000010 ri 7f"
  "rp 80000020 ri d"
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
