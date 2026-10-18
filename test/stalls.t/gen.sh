#!/bin/bash
# Writes stalls.vcd to stdout: a clock and a two-lane Dispatch module's inputs, set at each falling
# edge.
vars=(
  "1 a0 io_inst_0_valid" "1 b0 io_inst_0_ready" "32 c0 io_inst_0_bits_addr" "32 d0 io_inst_0_bits_inst"
  "1 a1 io_inst_1_valid" "1 b1 io_inst_1_ready" "32 c1 io_inst_1_bits_addr" "32 d1 io_inst_1_bits_inst"
  "1 t0 tryDispatch" "1 t1 tryDispatch_1" "32 s0 io_scoreboard_comb" "32 s1 comb_1"
  "1 h io_halted" "1 i io_interlock" "32 r io_scoreboard_regd" "4 n io_retirement_buffer_nSpace"
  "1 e io_retirement_buffer_empty" "1 p io_retirement_buffer_trap_pending" "4 q io_lsuQueueCapacity"
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
echo '$scope module dispatch $end'
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
# Per cycle, "id hex" changes; values hold. x10 (bit 10) is busy in cycles 0-2.
cycles=(
  "n 4 q 4 e 1 a0 1 b0 1 c0 100 d0 02a00513 a1 1 c1 104 d1 00a505b3 s1 400 s0 400"
  "b0 0 c0 104 d0 00a505b3 c1 108 d1 00b50633"
  ""
  "b0 1 s0 0 s1 0 a1 0"
  "a0 0"
  "a0 1 b0 0 c0 108 d0 00b50633 h 1"
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
