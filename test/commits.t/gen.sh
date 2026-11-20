#!/bin/bash
# Reads cycles from stdin, one per line, and writes a VCD to stdout: a core with one dispatch lane, one
# retirement lane and one register writeback port. A line holds any of
#   d PC WORD    a dispatch      w REG VALUE   a register write      r PC IDX   a retirement
# all in hex, and is blank for an idle cycle. Cycle N is set at the falling edge #(2N+2).
vars=(
  "1 df io_debug_dispatch_0_instFire" "32 da io_debug_dispatch_0_instAddr" "32 di io_debug_dispatch_0_instInst"
  "1 rv io_debug_rb_inst_0_valid" "32 rp io_debug_rb_inst_0_bits_pc" "7 ri io_debug_rb_inst_0_bits_idx"
  "1 rt io_debug_rb_inst_0_bits_trap" "1 wv io_debug_regfile_writeData_0_valid"
  "5 wa io_debug_regfile_writeData_0_bits_addr" "32 wd io_debug_regfile_writeData_0_bits_data"
)
declare -A width
bin() { # bin WIDTH HEX: the value at full width
  local w=$1 v=$((16#$2)) b="" i
  for ((i = w - 1; i >= 0; i--)); do b+=$(((v >> i) & 1)); done
  echo "b$b"
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
t=0
tick() {
  echo "#$((t + 1))"
  echo 1ck
  echo "#$((t + 2))"
  echo 0ck
  t=$((t + 2))
}
while IFS= read -r line || [ -n "$line" ]; do
  tick
  df=0 rv=0 wv=0
  set -- $line
  while [ $# -gt 0 ]; do
    case $1 in
      d) df=1 da=$2 di=$3 ;;
      w) wv=1 wa=$2 wd=$3 ;;
      r) rv=1 rp=$2 ri=$3 ;;
    esac
    shift 3
  done
  echo "b$df df"; echo "b$rv rv"; echo "b$wv wv"
  [ $df = 1 ] && { echo "$(bin 32 $da) da"; echo "$(bin 32 $di) di"; }
  [ $wv = 1 ] && { echo "$(bin 5 $wa) wa"; echo "$(bin 32 $wd) wd"; }
  [ $rv = 1 ] && { echo "$(bin 32 $rp) rp"; echo "$(bin 7 $ri) ri"; }
done
tick
echo "b0 df"; echo "b0 rv"; echo "b0 wv"
