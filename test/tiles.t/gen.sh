#!/bin/bash
# Writes tiles.vcd to stdout: a clock and a one-block, one-port VME tile register file's write port
# (4 tiles of 4 sub-tiles of 4 bytes), set at each falling edge.
vars=(
  "4 e writeEn" "4 p peWriteEn" "32 c peWritePc" "2 t writeMtIdx" "2 s writeSubIdx" "32 d writeData"
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
echo '$scope module vme $end'
for v in "${vars[@]}"; do set -- $v; width[$2]=$1; echo "\$var wire $1 $2 $3 \$end"; done
echo '$upscope $end'
echo '$upscope $end'
echo '$upscope $end'
echo '$enddefinitions $end'
echo '#0'
echo '$dumpvars'
echo 0ck
for v in "${vars[@]}"; do set -- $v; echo "b0 $2"; done
echo '$end'
# A tile load of tile 1 sub 2, then two PE writes to tile 3 sub 0, the second of its upper half.
cycles=(
  "e f t 1 s 2 d 11223344"
  "e 0"
  "e f p f c 200 t 3 s 0 d aabbccdd"
  "e c p c d 55660000"
  "e 0 p 0"
)
t=0
for c in "${cycles[@]}"; do
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
echo "#$((t + 1))"
echo 1ck
