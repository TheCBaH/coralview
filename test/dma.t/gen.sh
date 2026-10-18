#!/bin/bash
# Writes dma.vcd to stdout: a DMA engine's host and CSR ports, and the core's request interface.
declare -A width
vars=("1 ck io_clk_i")
dma=()
for p in host device; do
  c=${p:0:1}; w=$([ $p = host ] && echo 16 || echo 4); z=$([ $p = host ] && echo 4 || echo 2)
  o=$([ $p = host ] && echo 6 || echo 10)
  dma+=("1 ${c}av io_tl_${p}_a_valid" "1 ${c}ar io_tl_${p}_a_ready" "3 ${c}ao io_tl_${p}_a_bits_opcode"
    "$z ${c}az io_tl_${p}_a_bits_size" "$o ${c}as io_tl_${p}_a_bits_source" "32 ${c}aa io_tl_${p}_a_bits_address"
    "$w ${c}am io_tl_${p}_a_bits_mask" "$((8*w)) ${c}ad io_tl_${p}_a_bits_data"
    "1 ${c}dv io_tl_${p}_d_valid" "$o ${c}ds io_tl_${p}_d_bits_source" "$((8*w)) ${c}dd io_tl_${p}_d_bits_data"
    "1 ${c}de io_tl_${p}_d_bits_error")
done
dma+=("1 hdr io_tl_host_d_ready")
lsu=("1 ev io_ebus_dbus_valid" "1 er io_ebus_dbus_ready" "1 ew io_ebus_dbus_write"
  "32 ea io_ebus_dbus_addr" "32 ep io_ebus_dbus_pc")
for v in "${vars[@]}" "${dma[@]}" "${lsu[@]}"; do set -- $v; width[$2]=$1; done
echo '$timescale 1ps $end'
echo '$scope module TOP $end'
echo '$scope module sub $end'
for v in "${vars[@]}"; do set -- $v; echo "\$var wire $1 $2 $3 \$end"; done
echo '$scope module dma $end'
for v in "${dma[@]}"; do set -- $v; echo "\$var wire $1 $2 $3 \$end"; done
echo '$upscope $end'
echo '$scope module lsu $end'
for v in "${lsu[@]}"; do set -- $v; echo "\$var wire $1 $2 $3 \$end"; done
echo '$upscope $end'
echo '$upscope $end'
echo '$upscope $end'
echo '$enddefinitions $end'
# set_ ID VALUE...: a value is a number, or 32-bit words most significant first, joined by ':'.
set_() {
  while [ $# -gt 0 ]; do
    local w=${width[$1]} s="" word
    if [ "$w" = 1 ]; then echo "$(($2))$1"; shift 2; continue; fi
    IFS=: read -ra words <<< "$2"
    for word in "${words[@]}"; do local v=$((word)) n=32; [ ${#words[@]} = 1 ] && n=$w
      for ((i=n-1;i>=0;i--)); do s+=$(( (v>>i)&1 )); done; done
    echo "b$s $1"; shift 2
  done
}
echo '#0'
echo '$dumpvars'
for v in "${vars[@]}" "${dma[@]}" "${lsu[@]}"; do set -- $v; set_ $2 0; done
set_ har 1 hdr 1 dar 1
echo '$end'
at() { echo "#$((2*$1+1))"; echo "1ck"; echo "#$((2*$1+2))"; echo "0ck"; }
# csr OPCODE ADDR DATA PC: the core's access and the request it becomes on the CSR port.
csr() { set_ ev 1 ew $(( $1 == 0 )) ea $2 ep $4 dav 1 dao $1 daa $2 dad $3 das 1 daz 2 dam 0xf; }
csr_done() { set_ dav 0 ddv 1 dds 1 ddd ${1:-0} er 1; }
idle_csr() { set_ ddv 0 ev 0 er 0; }
get() { set_ hav 1 hao 4 haa $1 haz $2 has 0; }
put() { set_ hav 1 hao 0 haa $1 haz $2 has 0; }
resp() { set_ hav 0 hdv 1 hds 0 hdd ${1:-0}; }
quiet() { set_ hdv 0; }
at 0
at 1; csr 0 0x40050008 0x20006000 0x100
at 2; csr_done
at 3; idle_csr; csr 0 0x40050000 3 0x104
at 4; csr_done
# Descriptor 1: 4 bytes from 0x20004000 to 0x10040, chained to 0x20006020.
at 5; idle_csr; get 0x20006000 4
at 6; resp 0x20006020:0x02000004:0x00010040:0x20004000
at 7; quiet; get 0x20006010 4
at 8; resp
at 9; quiet; get 0x20004000 2
# Software polls STATUS while it runs.
at 10; resp 0:0:0:0xcafe; csr 4 0x40050004 0 0x10c
at 11; quiet; put 0x00010040 2; csr_done 1
at 12; idle_csr; set_ hav 0
at 13; resp
# Descriptor 2 waits for the word at 0x20000100 to read 1 before its beat.
at 14; quiet; get 0x20006020 4
at 15; resp 0:0x22000004:0x00010050:0x20004010
at 16; quiet; get 0x20006030 4
at 17; resp 0:1:0xff:0x20000100
at 18; quiet; get 0x20000100 2
at 19; resp
at 20; quiet; get 0x20000100 2
at 21; resp 0:0:0:1
at 22; quiet; get 0x20004010 2
at 23; resp 0:0:0:0xbeef
at 24; quiet; put 0x00010050 2
at 25; resp
at 26; quiet; csr 4 0x40050004 0 0x10c
at 27; csr_done 2
# A write with no job running.
at 28; idle_csr; put 0x00010060 2
at 29; resp
at 30; quiet
at 31
