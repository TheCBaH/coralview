#!/bin/bash
# Writes registers.vcd (no argument) or bad.vcd (any argument) to stdout: a core with one dispatch and
# retirement lane, one writeback port, x1-x3 and f0. addi x1 and addi x2 are announced (the marks),
# written back, stored one sample later and retired; the pipeline flushes in cycle 4. bad.vcd stores 9
# in x2 where 7 was written back.
bad=$1
declare -A width
top=(
  "1 df io_debug_dispatch_0_instFire" "32 da io_debug_dispatch_0_instAddr" "32 di io_debug_dispatch_0_instInst"
  "1 rv io_debug_rb_inst_0_valid" "32 rp io_debug_rb_inst_0_bits_pc" "7 ri io_debug_rb_inst_0_bits_idx"
  "1 rt io_debug_rb_inst_0_bits_trap"
  "1 gv io_debug_regfile_writeData_0_valid" "5 ga io_debug_regfile_writeData_0_bits_addr"
  "32 gd io_debug_regfile_writeData_0_bits_data"
  "1 mv io_debug_regfile_writeAddr_0_valid" "5 ma io_debug_regfile_writeAddr_0_bits"
  "1 fv io_debug_float_writeAddr_valid" "5 fa io_debug_float_writeAddr_bits"
)
regfile=(
  "32 r1 regfile_1" "32 r2 regfile_2" "32 r3 regfile_3" "32 xs scoreboard" "32 xf flushed_scoreboard"
  "1 xl io_pipelineFlush"
)
fregfile=(
  "1 s0 fregfile_0_sign" "8 e0 fregfile_0_exponent" "23 m0 fregfile_0_mantissa" "32 fs scoreboard"
  "32 ff flushed_scoreboard" "1 fl io_pipelineFlush"
)
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
decl() { for v in "$@"; do set -- $v; width[$2]=$1; echo "\$var wire $1 $2 $3 \$end"; done; }
echo '$timescale 1ps $end'
echo '$scope module TOP $end'
echo '$scope module core $end'
echo '$var wire 1 ck io_aclk $end'
decl "${top[@]}"
echo '$scope module score $end'
echo '$scope module regfile $end'
decl "${regfile[@]}"
echo '$upscope $end'
echo '$scope module fRegfile $end'
decl "${fregfile[@]}"
echo '$upscope $end'
echo '$upscope $end'
echo '$upscope $end'
echo '$upscope $end'
echo '$enddefinitions $end'
echo '#0'
echo '$dumpvars'
echo 0ck
for id in "${!width[@]}"; do echo "b0 $id"; done
echo '$end'
if [ -n "$bad" ]; then x2=9; else x2=7; fi
# cycle: "id hex" ... (values hold until changed)
cycles=(
  "df 1 da 100 di 02a00093 mv 1 ma 1"
  "xs 2 gv 1 ga 1 gd 2a da 104 di 00700113 ma 2"
  "xs 4 r1 2a ga 2 gd 7 df 0 mv 0 rv 1 rp 100 ri 1"
  "xs 0 r2 $x2 gv 0 rp 104 ri 2"
  "rv 0 xl 1"
  "xl 0"
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
