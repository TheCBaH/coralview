An RV32 image with two functions: kernel has a vector loop body, a Zvt word, a branch back to its
start, a call to helper, and a word Rivet has no form for; helper ends in a word that is no 32-bit
encoding, with a $d mapping symbol that the listing does not consult (the toolchain marks Coral's Zvt
words as data too).

  $ K="00000513,cd287057,0202e007,02036407,02041057,0203e027,43e06057,feb512e3,010000ef,00008067,ffffffff,00000013"
  $ H="ff010113,00008067,d12345678"
  $ ../../tools/mkelf.exe img.elf 100 kernel=$K helper=$H

  $ coralview disasm img.elf
  kernel:
    00000100  00000513  addi x10, x0, 0
    00000104  cd287057  vsetivli x0, 16, e32, m4, ta, ma
    00000108  0202e007  vle32.v v0, 0(x5)
    0000010c  02036407  vle32.v v8, 0(x6)
    00000110  02041057  vfadd.vv v0, v0, v8
    00000114  0203e027  vse32.v v0, 0(x7)
    00000118  43e06057  vtzero mt0
    0000011c  feb512e3  bne x10, x11, -28  <kernel>
    00000120  010000ef  jal x1, 16  <helper>
    00000124  00008067  jalr x0, 0(x1)
    00000128  ffffffff  .word 0xffffffff
    0000012c  00000013  addi x0, x0, 0
  helper:
    00000130  ff010113  addi x2, x2, -16
    00000134  00008067  jalr x0, 0(x1)
    00000138  12345678  .word 0x12345678

A function is the slice of the listing from its label; sections and ranges select the same way:

  $ coralview disasm img.elf > all.txt
  $ coralview disasm --function helper img.elf
  helper:
    00000130  ff010113  addi x2, x2, -16
    00000134  00008067  jalr x0, 0(x1)
    00000138  12345678  .word 0x12345678
  $ sed -n '/^helper:/,$p' all.txt > helper.txt
  $ coralview disasm --function helper img.elf | diff - helper.txt && echo same
  same
  $ sed -n '1,/^helper:/p' all.txt | sed '$d' > kernel.txt
  $ coralview disasm --function kernel img.elf | diff - kernel.txt && echo same
  same
  $ coralview disasm --section .text img.elf | cmp - all.txt && echo same
  same
  $ coralview disasm --range 0x118-0x124 img.elf
    00000118  43e06057  vtzero mt0
    0000011c  feb512e3  bne x10, x11, -28  <kernel>
    00000120  010000ef  jal x1, 16  <helper>

The Zvt words are off without xcoralzvt:

  $ coralview disasm --features none,+m,+zve32x --range 0x118-0x11c img.elf
    00000118  43e06057  .word 0x43e06057

Each instruction as JSON, with its class and enclosing symbol:

  $ coralview disasm --format jsonl --range 0x104-0x110 img.elf
  {"address":260,"word":3441979479,"text":"vsetivli x0, 16, e32, m4, ta, ma","mnemonic":"vsetivli","class":"vector","symbol":"kernel"}
  {"address":264,"word":33742855,"text":"vle32.v v0, 0(x5)","mnemonic":"vle32.v","class":"vector-mem","symbol":"kernel"}
  {"address":268,"word":33776647,"text":"vle32.v v8, 0(x6)","mnemonic":"vle32.v","class":"vector-mem","symbol":"kernel"}
  $ coralview disasm --format jsonl --range 0x11c-0x12c img.elf | head -n 1
  {"address":284,"word":4273279715,"text":"bne x10, x11, -28","mnemonic":"bne","class":"branch","symbol":"kernel","target":"<kernel>"}

A stripped image lists without labels, and cannot be cut by function:

  $ ../../tools/mkelf.exe --strip bare.elf 100 kernel=$K helper=$H
  $ coralview disasm --range 0x100-0x108 bare.elf
    00000100  00000513  addi x10, x0, 0
    00000104  cd287057  vsetivli x0, 16, e32, m4, ta, ma
  $ coralview disasm --function kernel bare.elf
  bare.elf: no function kernel
  [2]

Errors name the file:

  $ coralview disasm --function absent img.elf
  img.elf: no function absent
  [2]
  $ coralview disasm --section .data img.elf
  img.elf: no executable section .data
  [2]
  $ echo not an elf > text.elf
  $ coralview disasm text.elf 2>&1 | head -n 1
  text.elf: e_ident at offset 0x0, size 0x10, extends past the 11-byte input
  $ cp img.elf rvc.elf
  $ printf '\005\000\000\000' | dd of=rvc.elf bs=1 seek=36 conv=notrunc 2>/dev/null
  $ coralview disasm rvc.elf
  rvc.elf: the ELF marks compressed instructions (RVC); only 4-byte words are listed
  [2]

`--vconfig` notes each vector instruction's configuration, from the vsetvli words that reach it
(here the vsetivli at the top of kernel, through the loop's back edge), and says so when none does,
as in a function that loads vectors before any vsetvli, or after a call:

  $ coralview disasm --vconfig --function kernel img.elf | sed -n 2,10p
    00000100  00000513  addi x10, x0, 0
    00000104  cd287057  vsetivli x0, 16, e32, m4, ta, ma
    00000108  0202e007  vle32.v v0, 0(x5)  # e32,m4,ta,ma avl 16
    0000010c  02036407  vle32.v v8, 0(x6)  # e32,m4,ta,ma avl 16
    00000110  02041057  vfadd.vv v0, v0, v8  # e32,m4,ta,ma avl 16
    00000114  0203e027  vse32.v v0, 0(x7)  # e32,m4,ta,ma avl 16
    00000118  43e06057  vtzero mt0
    0000011c  feb512e3  bne x10, x11, -28  <kernel>
    00000120  010000ef  jal x1, 16  <helper>
  $ ../../tools/mkelf.exe bare.elf 100 bare=0202e007,00008067 after=cd287057,010000ef,0202e007,00008067
  $ coralview disasm --vconfig bare.elf
  bare:
    00000100  0202e007  vle32.v v0, 0(x5)  # vtype unknown
    00000104  00008067  jalr x0, 0(x1)
  after:
    00000108  cd287057  vsetivli x0, 16, e32, m4, ta, ma
    0000010c  010000ef  jal x1, 16
    00000110  0202e007  vle32.v v0, 0(x5)  # vtype unknown
    00000114  00008067  jalr x0, 0(x1)
  $ coralview disasm --vconfig --format jsonl --function kernel img.elf | sed -n 3p
  {"address":264,"word":33742855,"text":"vle32.v v0, 0(x5)","mnemonic":"vle32.v","class":"vector-mem","symbol":"kernel","vconfig":"e32,m4,ta,ma avl 16"}

`--annotate` joins a sidecar of labels: `NAME` is a whole function, `NAME+OFF` a byte, `NAME+OFF-OFF` a
range (end excluded), and `0xADDR[-0xADDR]` the same by address. A producer that knows where its code came
from writes it; the labels follow the instruction as `; label`:

  $ cat > labels.txt <<'LABELS'
  > # where each part of kernel came from
  > kernel+4-0x1c   vector body of residual_add
  > kernel+0x1c     loop back edge
  > helper          shared helper
  > 0x130-0x134     helper prologue
  > LABELS
  $ coralview disasm --annotate labels.txt img.elf
  kernel:
    00000100  00000513  addi x10, x0, 0
    00000104  cd287057  vsetivli x0, 16, e32, m4, ta, ma  ; vector body of residual_add
    00000108  0202e007  vle32.v v0, 0(x5)  ; vector body of residual_add
    0000010c  02036407  vle32.v v8, 0(x6)  ; vector body of residual_add
    00000110  02041057  vfadd.vv v0, v0, v8  ; vector body of residual_add
    00000114  0203e027  vse32.v v0, 0(x7)  ; vector body of residual_add
    00000118  43e06057  vtzero mt0  ; vector body of residual_add
    0000011c  feb512e3  bne x10, x11, -28  <kernel>  ; loop back edge
    00000120  010000ef  jal x1, 16  <helper>
    00000124  00008067  jalr x0, 0(x1)
    00000128  ffffffff  .word 0xffffffff
    0000012c  00000013  addi x0, x0, 0
  helper:
    00000130  ff010113  addi x2, x2, -16  ; shared helper; helper prologue
    00000134  00008067  jalr x0, 0(x1)  ; shared helper
    00000138  12345678  .word 0x12345678  ; shared helper
  $ coralview disasm --annotate labels.txt --format jsonl --function helper img.elf | sed -n 1p
  {"address":304,"word":4278255891,"text":"addi x2, x2, -16","mnemonic":"addi","class":"alu","symbol":"helper","annotation":"shared helper; helper prologue"}
  $ printf 'nowhere+4 lost\n' > bad.txt
  $ coralview disasm --annotate bad.txt img.elf
  --annotate: bad.txt: line 1: no function nowhere in the ELF
  [2]
  $ printf 'kernel\n' > bad.txt
  $ coralview disasm --annotate bad.txt img.elf
  --annotate: bad.txt: line 1: expected LOCATION LABEL
  [2]
