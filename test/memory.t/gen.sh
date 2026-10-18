#!/bin/bash
# Writes memory.vcd to stdout: a clock and the LSU's TCM and external data buses and fault port, set at
# each falling edge.
vars=(
  "1 tv io_dbus_valid" "1 tr io_dbus_ready" "1 tw io_dbus_write" "32 ta io_dbus_addr"
  "16 tm io_dbus_wmask" "128 td io_dbus_wdata" "128 tq io_dbus_rdata"
  "1 ev io_ebus_dbus_valid" "1 er io_ebus_dbus_ready" "1 ew io_ebus_dbus_write" "32 ea io_ebus_dbus_addr"
  "16 em io_ebus_dbus_wmask" "128 ed io_ebus_dbus_wdata" "128 eq io_ebus_dbus_rdata" "32 ep io_ebus_dbus_pc"
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
echo '$upscope $end'
echo '$upscope $end'
echo '$upscope $end'
echo '$enddefinitions $end'
echo '#0'
echo '$dumpvars'
echo 0ck
for v in "${vars[@]}"; do set -- $v; echo "b0 $2"; done
echo '$end'
# cycle: "id hex" ... (values hold until changed)
cycles=(
  "tv 1 tr 1 tw 1 ta 10004 tm 00f0 td 00000000000000000000deadbeef00000000 ep 100"
  "tw 0 ta 10008 tm 0 td 0 ep 104"
  "tv 0 tq 00000000112233440000000000000000"
  "ev 1 er 1 ew 1 ea 20000000 em 000f ed cafef00d ep 108"
  "ew 0 ea 20000010 em 0 ed 0 ep 10c"
  "ev 0 eq 55667788 fv 1 fa 30000000 fe 10c"
  "fw 1 fa 40 fe 110"
  "fv 0 fw 0"
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
