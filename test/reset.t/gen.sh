#!/bin/bash
# core.vcd with io_aresetn and two reset cycles in front: its values are unknown or garbage while
# io_aresetn is 0, and its own timeline starts at #6.
core=../platform.t/core.vcd
sed -n '1,5p' $core
echo '$var wire 1 R io_aresetn $end'
sed -n '6,$p' $core | sed -n '1,/^#0$/p' | sed '$d'
cat <<'END'
#0
$dumpvars
0!
0R
x"
bx #
bx $
0%
bx &
bx '
x(
0)
bx *
bx +
$end
#1
1!
#2
0!
1"
b10000000000000000000000001000 #
b10011 $
#3
1!
#4
0!
0"
1%
b100000000000000 &
b101 '
x(
1)
b1 *
bx +
#5
1!
#6
0!
1R
0"
b0 #
b0 $
0%
b0 &
b0 '
0(
0)
b0 *
b0 +
END
# the core's own timeline, from #1, six timestamps later
awk '/^#0$/ {p=1; next} p && /^\$dumpvars/ {next} p' $core | awk '
  /^\$end$/ && !seen {seen=1; next}
  /^#[0-9]+$/ {t=substr($0,2)+6; print "#" t; started=1; next}
  started {print}'
