#!/bin/bash
# Writes ops.vcd to stdout: a clock, one scalar dispatch lane and two RVV backend dispatch lanes whose
# uops are { uop_pc:32, uop_exe_unit:5, csr_vl:8, csr_vstart:7, csr_sew:3, csr_lmul:3, first_uop_valid:1 },
# set at each falling edge.
bits() { # bits WIDTH VALUE
  local w=$1 v=$2 b="" i
  for ((i = w - 1; i >= 0; i--)); do b+=$(((v >> i) & 1)); done
  echo "$b"
}
uop() { # uop PC UNIT VL VSTART SEW LMUL FIRST
  echo "$(bits 32 $1)$(bits 5 $2)$(bits 8 $3)$(bits 7 $4)$(bits 3 $5)$(bits 3 $6)$(bits 1 $7)"
}
none=$(uop 0 0 0 0 0 0 0)
echo '$timescale 1ps $end'
echo '$scope module TOP $end'
echo '$scope module core $end'
echo '$var wire 1 ck io_aclk $end'
echo '$var wire 1 f io_debug_dispatch_0_instFire $end'
echo '$var wire 32 a io_debug_dispatch_0_instAddr $end'
echo '$var wire 32 i io_debug_dispatch_0_instInst $end'
echo '$scope module backend $end'
echo '$var wire 2 v uv $end'
echo '$var wire 2 r ur $end'
echo '$var wire 118 u uop $end'
echo '$upscope $end'
echo '$upscope $end'
echo '$upscope $end'
echo '$enddefinitions $end'
echo '#0'
echo '$dumpvars'
echo 0ck
echo 0f
echo "b$(bits 32 0) a"
echo "b$(bits 32 0) i"
echo "b00 v"
echo "b00 r"
echo "b$none$none u"
echo '$end'
# Per cycle: the scalar dispatch (PC and word, or -), the backend's valid and ready bits, and its
# two lanes' uops (lane 1 first). Units: alu 0, lsu 7, fma 8; SEW 2 is 32 bits.
cycles=(
  "0x100 0xb387d857 00 00 - -"
  "0x104 0x02056407 01 01 - 0x100,8,8,0,2,0,1"
  "0x108 0x02218057 11 11 0x100,8,8,0,2,0,0 0x104,7,8,0,2,0,1"
  "- - 01 01 - 0x108,0,6,2,2,0,1"
  "0x10c 0x5e003257 00 00 - -"
  "- - 01 01 - 0x10c,0,8,0,2,0,1"
  "- - 01 00 - 0x108,0,6,2,2,0,1"
  "- - 00 00 - -"
  "- - 00 00 - -"
  "- - 01 01 - 0x100,8,4,0,2,0,1"
  "- - 01 01 - 0x200,0,2,0,2,0,1"
  "- - 00 00 - -"
)
lane() { if [ "$1" = - ]; then echo "$none"; else IFS=, read -r p u l s e m f <<< "$1"; uop $((p)) $u $l $s $e $m $f; fi; }
t=0
for c in "${cycles[@]}"; do
  set -- $c
  echo "#$((t + 1))"
  echo 1ck
  echo "#$((t + 2))"
  echo 0ck
  if [ "$1" = - ]; then echo 0f; else echo 1f; echo "b$(bits 32 $(($1))) a"; echo "b$(bits 32 $(($2))) i"; fi
  echo "b$3 v"
  echo "b$4 r"
  echo "b$(lane $5)$(lane $6) u"
  t=$((t + 2))
done
echo "#$((t + 1))"
echo 1ck
