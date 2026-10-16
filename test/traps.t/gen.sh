#!/bin/bash
# Writes traps.vcd to stdout.
bin() { local w=$1 v=$2 s=""; for ((i=w-1;i>=0;i--)); do s+=$(( (v>>i)&1 )); done; echo "$s"; }
cat <<H
\$timescale 1ps \$end
\$scope module TOP \$end
\$scope module core \$end
\$var wire 1 ! io_aclk \$end
\$var wire 1 " io_debug_dispatch_0_instFire \$end
\$var wire 32 # io_debug_dispatch_0_instAddr \$end
\$var wire 32 \$ io_debug_dispatch_0_instInst \$end
\$var wire 1 % io_debug_rb_inst_0_valid \$end
\$var wire 32 & io_debug_rb_inst_0_bits_pc \$end
\$var wire 7 ' io_debug_rb_inst_0_bits_idx \$end
\$var wire 1 ( io_debug_rb_inst_0_bits_trap \$end
\$scope module fm \$end
\$var wire 1 ) io_out_valid \$end
\$var wire 32 * io_out_bits_mcause \$end
\$var wire 32 + io_out_bits_mepc \$end
\$var wire 32 , io_out_bits_mtval \$end
\$var wire 1 - io_out_bits_decode \$end
\$var wire 1 . io_in_memory_fault_valid \$end
\$var wire 1 / io_in_memory_fault_bits_write \$end
\$var wire 1 0 io_in_fetchFault_valid \$end
\$upscope \$end
\$scope module csr \$end
\$var wire 32 1 mcause \$end
\$var wire 32 2 mepc \$end
\$var wire 32 3 mtval \$end
\$var wire 32 4 mtvec \$end
\$upscope \$end
\$upscope \$end
\$upscope \$end
\$enddefinitions \$end
#0
\$dumpvars
0!
0"
b0 #
b0 \$
0%
b0 &
b1111111 '
0(
0)
b0 *
b0 +
b0 ,
0-
0.
0/
00
b0 1
b0 2
b0 3
b$(bin 32 0x41) 4
\$end
H
at() { echo "#$((2*$1+1))"; echo "1!"; echo "#$((2*$1+2))"; echo "0!"; }
w() { echo "b$(bin 32 $2) $1"; }
fault() { echo "1)"; w '*' $1; w + $2; w , $3; }
nofault() { echo "0)"; w '*' 0; w + 0; w , 0; echo "0."; echo "0/"; }
retire() { echo "1%"; w '&' $1; echo "$2("; }
dispatch() { echo '1"'; w '#' $1; w '$' 0x13; }
at 0
at 1; dispatch 0x10
at 2; echo '0"'; fault 7 0x10 0x100; echo "1."; echo "1/"
at 3; nofault; w 1 7; w 2 0x10; w 3 0x100; retire 0x10 1
at 4; echo "0%"; echo "0("; dispatch 0x40
at 5; echo '0"'; retire 0x40 0
at 6; echo "0%"; w 2 0x14
at 7; retire 0x20 0
at 8; echo "0%"; fault 5 0x20 0x3000; echo "1."
at 9; nofault; w 1 5; w 2 0x20; w 3 0x3000
at 10; dispatch 0x40
at 11; echo '0"'
at 12
