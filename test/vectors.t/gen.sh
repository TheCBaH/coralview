#!/bin/bash
# Writes vectors.vcd (no argument) or bad.vcd (any argument) to stdout.
bad=$1
bin() { local w=$1 v=$2 s=""; for ((i=w-1;i>=0;i--)); do s+=$(( (v>>i)&1 )); done; echo "$s"; }
entry() { echo "$(bin 32 $1)$(bin 1 $2)$(bin 16 $3)$(bin 2 $4)"; }   # pc idx data strobe
idle=$(entry 0 0 0 0)
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
\$var wire 1 ) io_debug_regfile_writeData_0_valid \$end
\$var wire 5 * io_debug_regfile_writeData_0_bits_addr \$end
\$var wire 32 + io_debug_regfile_writeData_0_bits_data \$end
\$scope module vrf \$end
\$var wire 32 , vreg \$end
\$var wire 2 - wr_valid \$end
\$var wire 102 . wr_data \$end
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
b0 '
0(
0)
b0 *
b0 +
b0 ,
b0 -
b$idle$idle .
\$end
H
# cycle k: changes at the falling edge 2k+2
at() { echo "#$((2*$1+1))"; echo "1!"; echo "#$((2*$1+2))"; echo "0!"; }
retire() { echo "1%"; echo "b$(bin 32 $1) &"; echo "b$(bin 7 $2) '"; }
at 0
at 1; echo "b01 -"; echo "b$idle$(entry 0x100 0 0x00ab 1) ."
at 2; echo "b$(bin 32 0x000000ab) ,"; echo "b11 -"; echo "b$(entry 0x104 0 0x0011 1)$(entry 0x104 0 0xcd00 2) ."; retire 0x100 64
if [ -n "$bad" ]; then s3=0x0000cdab; else s3=0x0000cd11; fi
at 3; echo "b$(bin 32 $s3) ,"; echo "b11 -"; echo "b$(entry 0x108 1 0xbeef 3)$(entry 0x108 0 0xee00 2) ."; retire 0x104 64
at 4; echo "b$(bin 32 $(( 0xbeef0000 | 0xee00 | (s3 & 0xff) ))) ,"; echo "b00 -"; echo "b$idle$idle ."; if [ -n "$bad" ]; then retire 0x10c 65; else retire 0x108 65; fi
at 5; echo "0%"
at 6
