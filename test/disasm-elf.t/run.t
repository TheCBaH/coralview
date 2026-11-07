Two images from the Coral NPU release the devcontainer pins (v0.0.8, examples/), kept here as they ship:
matrix.elf, whose Zvt matrix words the toolchain writes as .word and
marks as data, and rvv_fp.elf, with scalar and vector floating point. The listing is the expected
output of the whole of matrix.elf.

  $ coralview disasm matrix.elf
  _start:
    00000000  b0205073  csrwi minstret, 0
    00000004  b8205073  csrwi minstreth, 0
    00000008  b0202573  csrr x10, minstret
    0000000c  b82025f3  csrr x11, minstreth
    00000010  00018117  auipc x2, 24
    00000014  ff010113  addi x2, x2, -16
    00000018  00011197  auipc x3, 17
    0000001c  8b818193  addi x3, x3, -1864
    00000020  00000213  addi x4, x0, 0
    00000024  00000313  addi x6, x0, 0
    00000028  00000393  addi x7, x0, 0
    0000002c  00000413  addi x8, x0, 0
    00000030  00000493  addi x9, x0, 0
    00000034  00000593  addi x11, x0, 0
    00000038  00000613  addi x12, x0, 0
    0000003c  00000693  addi x13, x0, 0
    00000040  00000713  addi x14, x0, 0
    00000044  00000793  addi x15, x0, 0
    00000048  00000813  addi x16, x0, 0
    0000004c  00000893  addi x17, x0, 0
    00000050  00000913  addi x18, x0, 0
    00000054  00000993  addi x19, x0, 0
    00000058  00000a13  addi x20, x0, 0
    0000005c  00000a93  addi x21, x0, 0
    00000060  00000b13  addi x22, x0, 0
    00000064  00000b93  addi x23, x0, 0
    00000068  00000c13  addi x24, x0, 0
    0000006c  00000c93  addi x25, x0, 0
    00000070  00000d13  addi x26, x0, 0
    00000074  00000d93  addi x27, x0, 0
    00000078  00000e13  addi x28, x0, 0
    0000007c  00000e93  addi x29, x0, 0
    00000080  00000f13  addi x30, x0, 0
    00000084  00000f93  addi x31, x0, 0
    00000088  86018513  addi x10, x3, -1952
    0000008c  00010597  auipc x11, 16
    00000090  0ac58593  addi x11, x11, 172
    00000094  62c000ef  jal x1, 1580  <crt_section_clear>
    00000098  73000413  addi x8, x0, 1840
    0000009c  73000493  addi x9, x0, 1840
    000000a0  00947a63  bgeu x8, x9, 20  <init_array_loop_end>
  init_array_loop:
    000000a4  00042283  lw x5, 0(x8)
    000000a8  000280e7  jalr x1, 0(x5)
    000000ac  00440413  addi x8, x8, 4
    000000b0  fe946ae3  bltu x8, x9, -12  <init_array_loop>
  init_array_loop_end:
    000000b4  00000297  auipc x5, 0
    000000b8  37c28293  addi x5, x5, 892
    000000bc  30529073  csrw mtvec, x5
    000000c0  000062b7  lui x5, 6
    000000c4  60028293  addi x5, x5, 1536
    000000c8  3002a073  csrs mstatus, x5
    000000cc  00010297  auipc x5, 16
    000000d0  05428293  addi x5, x5, 84
    000000d4  0badd537  lui x10, 47837
    000000d8  00d50513  addi x10, x10, 13
    000000dc  00a2a023  sw x10, 0(x5)
    000000e0  00000513  addi x10, x0, 0
    000000e4  00000593  addi x11, x0, 0
    000000e8  00000097  auipc x1, 0
    000000ec  05c08093  addi x1, x1, 92
    000000f0  000080e7  jalr x1, 0(x1)
    000000f4  00050913  addi x18, x10, 0
    000000f8  428000ef  jal x1, 1064  <__cxa_finalize>
    000000fc  73000413  addi x8, x0, 1840
    00000100  73000493  addi x9, x0, 1840
    00000104  00940a63  beq x8, x9, 20  <fini_array_loop_end>
  fini_array_loop:
    00000108  ffc48493  addi x9, x9, -4
    0000010c  0004a283  lw x5, 0(x9)
    00000110  000280e7  jalr x1, 0(x5)
    00000114  fe941ae3  bne x8, x9, -12  <fini_array_loop>
  fini_array_loop_end:
    00000118  00090513  addi x10, x18, 0
    0000011c  00010297  auipc x5, 16
    00000120  00428293  addi x5, x5, 4
    00000124  00a2a023  sw x10, 0(x5)
    00000128  00050663  beq x10, x0, 12  <success>
  failure:
    0000012c  00100073  ebreak
    00000130  0100006f  jal x0, 16  <loop>
  success:
    00000134  b0202573  csrr x10, minstret
    00000138  b82025f3  csrr x11, minstreth
    0000013c  08000073  mpause
  loop:
    00000140  0000006f  jal x0, 0  <loop>
  main:
    00000144  fe010113  addi x2, x2, -32
    00000148  00112e23  sw x1, 28(x2)
    0000014c  600007b7  lui x15, 393216
    00000150  3007a073  csrs mstatus, x15
    00000154  000017b7  lui x15, 1
    00000158  84378793  addi x15, x15, -1981
    0000015c  0c000713  addi x14, x0, 192
    00000160  84e7f057  msetmtype x15, x14
    00000164  00200793  addi x15, x0, 2
    00000168  8807f7d7  msettn x15, x15
    0000016c  c2302773  csrr x14, 0xc23
    00000170  fbd70713  addi x14, x14, -67
    00000174  80070713  addi x14, x14, -2048
    00000178  ffe78793  addi x15, x15, -2
    0000017c  00173713  sltiu x14, x14, 1
    00000180  0017b793  sltiu x15, x15, 1
    00000184  00e7f7b3  and x15, x15, x14
    00000188  24078a63  beq x15, x0, 596  <main+0x298>
    0000018c  43e06057  vtzero mt0
    00000190  75400793  addi x15, x0, 1876
    00000194  75600713  addi x14, x0, 1878
    00000198  75000693  addi x13, x0, 1872
    0000019c  75200613  addi x12, x0, 1874
    000001a0  02078407  vle8.v v8, 0(x15)
    000001a4  02070507  vle8.v v10, 0(x14)
    000001a8  02068807  vle8.v v16, 0(x13)
    000001ac  02060907  vle8.v v18, 0(x12)
    000001b0  f28800f7  vtmms.tvv mt0, v8, v16
    000001b4  00000613  addi x12, x0, 0
    000001b8  52c17027  vtse32 x12, 0(x2)
    000001bc  00100693  addi x13, x0, 1
    000001c0  00810793  addi x15, x2, 8
    000001c4  52d7f027  vtse32 x13, 0(x15)
    000001c8  00012583  lw x11, 0(x2)
    000001cc  ff000513  addi x10, x0, -16
    000001d0  20a59663  bne x11, x10, 524  <main+0x298>
    000001d4  00412803  lw x16, 4(x2)
    000001d8  fee00513  addi x10, x0, -18
    000001dc  20a81063  bne x16, x10, 512  <main+0x298>
    000001e0  00812803  lw x16, 8(x2)
    000001e4  01200513  addi x10, x0, 18
    000001e8  1ea81a63  bne x16, x10, 500  <main+0x298>
    000001ec  00c12803  lw x16, 12(x2)
    000001f0  01400513  addi x10, x0, 20
    000001f4  1ea81463  bne x16, x10, 488  <main+0x298>
    000001f8  f28800f7  vtmms.tvv mt0, v8, v16
    000001fc  52c17027  vtse32 x12, 0(x2)
    00000200  52d7f027  vtse32 x13, 0(x15)
    00000204  00012803  lw x16, 0(x2)
    00000208  fe000513  addi x10, x0, -32
    0000020c  1ca81863  bne x16, x10, 464  <main+0x298>
    00000210  00412803  lw x16, 4(x2)
    00000214  fdc00513  addi x10, x0, -36
    00000218  1ca81263  bne x16, x10, 452  <main+0x298>
    0000021c  00812803  lw x16, 8(x2)
    00000220  02400513  addi x10, x0, 36
    00000224  1aa81c63  bne x16, x10, 440  <main+0x298>
    00000228  00c12803  lw x16, 12(x2)
    0000022c  02800513  addi x10, x0, 40
    00000230  1aa81663  bne x16, x10, 428  <main+0x298>
    00000234  43e06057  vtzero mt0
    00000238  f28800f7  vtmms.tvv mt0, v8, v16
    0000023c  52c17027  vtse32 x12, 0(x2)
    00000240  52d7f027  vtse32 x13, 0(x15)
    00000244  00012683  lw x13, 0(x2)
    00000248  18b69a63  bne x13, x11, 404  <main+0x298>
    0000024c  00412603  lw x12, 4(x2)
    00000250  fee00693  addi x13, x0, -18
    00000254  18d61463  bne x12, x13, 392  <main+0x298>
    00000258  00812603  lw x12, 8(x2)
    0000025c  01200693  addi x13, x0, 18
    00000260  16d61e63  bne x12, x13, 380  <main+0x298>
    00000264  00c12603  lw x12, 12(x2)
    00000268  01400693  addi x13, x0, 20
    0000026c  16d61863  bne x12, x13, 368  <main+0x298>
    00000270  000016b7  lui x13, 1
    00000274  82168693  addi x13, x13, -2015
    00000278  0d200613  addi x12, x0, 210
    0000027c  84c6f057  msetmtype x13, x12
    00000280  00200613  addi x12, x0, 2
    00000284  880675d7  msettn x11, x12
    00000288  c23026f3  csrr x13, 0xc23
    0000028c  ffe58593  addi x11, x11, -2
    00000290  16059863  bne x11, x0, 368  <main+0x2bc>
    00000294  fdf68693  addi x13, x13, -33
    00000298  80068693  addi x13, x13, -2048
    0000029c  16069263  bne x13, x0, 356  <main+0x2bc>
    000002a0  43e06057  vtzero mt0
    000002a4  74800693  addi x13, x0, 1864
    000002a8  74000593  addi x11, x0, 1856
    000002ac  0206e407  vle32.v v8, 0(x13)
    000002b0  0205e807  vle32.v v16, 0(x11)
    000002b4  f2881077  vtfmm.tvv mt0, v8, v16
    000002b8  00000693  addi x13, x0, 0
    000002bc  52d17027  vtse32 x13, 0(x2)
    000002c0  00100693  addi x13, x0, 1
    000002c4  52d7f027  vtse32 x13, 0(x15)
    000002c8  00000697  auipc x13, 0
    000002cc  4906a787  flw f15, 1168(x13)
    000002d0  00012707  flw f14, 0(x2)
    000002d4  a0f726d3  feq.s x13, f14, f15
    000002d8  12068463  beq x13, x0, 296  <main+0x2bc>
    000002dc  00000697  auipc x13, 0
    000002e0  4806a787  flw f15, 1152(x13)
    000002e4  00412707  flw f14, 4(x2)
    000002e8  a0f726d3  feq.s x13, f14, f15
    000002ec  10068a63  beq x13, x0, 276  <main+0x2bc>
    000002f0  00812707  flw f14, 8(x2)
    000002f4  a0f726d3  feq.s x13, f14, f15
    000002f8  10068463  beq x13, x0, 264  <main+0x2bc>
    000002fc  00000697  auipc x13, 0
    00000300  4646a787  flw f15, 1124(x13)
    00000304  00c12707  flw f14, 12(x2)
    00000308  a0f726d3  feq.s x13, f14, f15
    0000030c  0e068a63  beq x13, x0, 244  <main+0x2bc>
    00000310  000016b7  lui x13, 1
    00000314  84268693  addi x13, x13, -1982
    00000318  1c900593  addi x11, x0, 457
    0000031c  84b6f057  msetmtype x13, x11
    00000320  88067657  msettn x12, x12
    00000324  c23026f3  csrr x13, 0xc23
    00000328  ffe60613  addi x12, x12, -2
    0000032c  0e061663  bne x12, x0, 236  <main+0x2d4>
    00000330  fbe68693  addi x13, x13, -66
    00000334  80068693  addi x13, x13, -2048
    00000338  0e069063  bne x13, x0, 224  <main+0x2d4>
    0000033c  43e06057  vtzero mt0
    00000340  73800693  addi x13, x0, 1848
    00000344  73c00613  addi x12, x0, 1852
    00000348  73000593  addi x11, x0, 1840
    0000034c  73400513  addi x10, x0, 1844
    00000350  0206d407  vle16.v v8, 0(x13)
    00000354  02065607  vle16.v v12, 0(x12)
    00000358  0205d807  vle16.v v16, 0(x11)
    0000035c  02055a07  vle16.v v20, 0(x10)
    00000360  f28810f7  vtfmm.alt.tvv mt0, v8, v16
    00000364  00000693  addi x13, x0, 0
    00000368  52d17027  vtse32 x13, 0(x2)
    0000036c  00100713  addi x14, x0, 1
    00000370  52e7f027  vtse32 x14, 0(x15)
    00000374  00000797  auipc x15, 0
    00000378  3f07a787  flw f15, 1008(x15)
    0000037c  00012707  flw f14, 0(x2)
    00000380  a0f727d3  feq.s x15, f14, f15
    00000384  08078a63  beq x15, x0, 148  <main+0x2d4>
    00000388  00000797  auipc x15, 0
    0000038c  3e07a787  flw f15, 992(x15)
    00000390  00412707  flw f14, 4(x2)
    00000394  a0f727d3  feq.s x15, f14, f15
    00000398  08078063  beq x15, x0, 128  <main+0x2d4>
    0000039c  00000797  auipc x15, 0
    000003a0  3d07a787  flw f15, 976(x15)
    000003a4  00812707  flw f14, 8(x2)
    000003a8  a0f727d3  feq.s x15, f14, f15
    000003ac  06078663  beq x15, x0, 108  <main+0x2d4>
    000003b0  00000797  auipc x15, 0
    000003b4  3c07a787  flw f15, 960(x15)
    000003b8  00c12707  flw f14, 12(x2)
    000003bc  a0f727d3  feq.s x15, f14, f15
    000003c0  04078c63  beq x15, x0, 88  <main+0x2d4>
    000003c4  00100513  addi x10, x0, 1
    000003c8  01200613  addi x12, x0, 18
    000003cc  7bc00593  addi x11, x0, 1980
    000003d0  15c000ef  jal x1, 348  <write>
    000003d4  00000513  addi x10, x0, 0
    000003d8  01c0006f  jal x0, 28  <main+0x2b0>
    000003dc  01700613  addi x12, x0, 23
    000003e0  00000597  auipc x11, 0
    000003e4  39458593  addi x11, x11, 916
    000003e8  00100513  addi x10, x0, 1
    000003ec  140000ef  jal x1, 320  <write>
    000003f0  00100513  addi x10, x0, 1
    000003f4  01c12083  lw x1, 28(x2)
    000003f8  02010113  addi x2, x2, 32
    000003fc  00008067  jalr x0, 0(x1)
    00000400  01700613  addi x12, x0, 23
    00000404  00000597  auipc x11, 0
    00000408  38858593  addi x11, x11, 904
    0000040c  00100513  addi x10, x0, 1
    00000410  11c000ef  jal x1, 284  <write>
    00000414  fddff06f  jal x0, -36  <main+0x2ac>
    00000418  01700613  addi x12, x0, 23
    0000041c  00000597  auipc x11, 0
    00000420  38858593  addi x11, x11, 904
    00000424  00100513  addi x10, x0, 1
    00000428  104000ef  jal x1, 260  <write>
    0000042c  fc5ff06f  jal x0, -60  <main+0x2ac>
  coralnpu_exception_handler:
    00000430  00100073  ebreak
    00000434  0000006f  jal x0, 0  <coralnpu_exception_handler+0x4>
  _write:
    00000438  fc010113  addi x2, x2, -64
    0000043c  04000713  addi x14, x0, 64
    00000440  00e12023  sw x14, 0(x2)
    00000444  00000793  addi x15, x0, 0
    00000448  00f12223  sw x15, 4(x2)
    0000044c  00a12423  sw x10, 8(x2)
    00000450  41f55893  srai x17, x10, 31
    00000454  01112623  sw x17, 12(x2)
    00000458  00058693  addi x13, x11, 0
    0000045c  00d12823  sw x13, 16(x2)
    00000460  41f5d593  srai x11, x11, 31
    00000464  00b12a23  sw x11, 20(x2)
    00000468  00c12c23  sw x12, 24(x2)
    0000046c  41f65793  srai x15, x12, 31
    00000470  00f12e23  sw x15, 28(x2)
    00000474  02012023  sw x0, 32(x2)
    00000478  02012223  sw x0, 36(x2)
    0000047c  02012423  sw x0, 40(x2)
    00000480  02012623  sw x0, 44(x2)
    00000484  02012823  sw x0, 48(x2)
    00000488  02012a23  sw x0, 52(x2)
    0000048c  02012c23  sw x0, 56(x2)
    00000490  02012e23  sw x0, 60(x2)
    00000494  0310000f  fence rw, w
    00000498  00010697  auipc x13, 16
    0000049c  c2868693  addi x13, x13, -984
    000004a0  00000793  addi x15, x0, 0
    000004a4  0026a023  sw x2, 0(x13)
    000004a8  00f6a223  sw x15, 4(x13)
    000004ac  0310000f  fence rw, w
    000004b0  00010797  auipc x15, 16
    000004b4  b9078793  addi x15, x15, -1136
    000004b8  00100613  addi x12, x0, 1
    000004bc  00000693  addi x13, x0, 0
    000004c0  00c7a023  sw x12, 0(x15)
    000004c4  00d7a223  sw x13, 4(x15)
    000004c8  00010617  auipc x12, 16
    000004cc  b3860613  addi x12, x12, -1224
    000004d0  00010697  auipc x13, 16
    000004d4  bb068693  addi x13, x13, -1104
    000004d8  0006a703  lw x14, 0(x13)
    000004dc  0046a783  lw x15, 4(x13)
    000004e0  00f76733  or x14, x14, x15
    000004e4  02070463  beq x14, x0, 40  <_write+0xd4>
    000004e8  0006a023  sw x0, 0(x13)
    000004ec  0006a223  sw x0, 4(x13)
    000004f0  00062023  sw x0, 0(x12)
    000004f4  00062223  sw x0, 4(x12)
    000004f8  0230000f  fence r, rw
    000004fc  00012503  lw x10, 0(x2)
    00000500  00412583  lw x11, 4(x2)
    00000504  04010113  addi x2, x2, 64
    00000508  00008067  jalr x0, 0(x1)
    0000050c  00062703  lw x14, 0(x12)
    00000510  00462783  lw x15, 4(x12)
    00000514  00f76733  or x14, x14, x15
    00000518  fc0700e3  beq x14, x0, -64  <_write+0xa0>
    0000051c  fcdff06f  jal x0, -52  <_write+0xb0>
  __cxa_finalize:
    00000520  00050593  addi x11, x10, 0
    00000524  00000513  addi x10, x0, 0
    00000528  01c0006f  jal x0, 28  <__call_exitprocs>
  write:
    0000052c  00060693  addi x13, x12, 0
    00000530  00058613  addi x12, x11, 0
    00000534  00050593  addi x11, x10, 0
    00000538  00010517  auipc x10, 16
    0000053c  b9852503  lw x10, -1128(x10)
    00000540  12c0006f  jal x0, 300  <_write_r>
  __call_exitprocs:
    00000544  fd010113  addi x2, x2, -48
    00000548  01512a23  sw x21, 20(x2)
    0000054c  01612823  sw x22, 16(x2)
    00000550  01712623  sw x23, 12(x2)
    00000554  01912223  sw x25, 4(x2)
    00000558  02112623  sw x1, 44(x2)
    0000055c  02812423  sw x8, 40(x2)
    00000560  02912223  sw x9, 36(x2)
    00000564  03212023  sw x18, 32(x2)
    00000568  01312e23  sw x19, 28(x2)
    0000056c  01412c23  sw x20, 24(x2)
    00000570  01812423  sw x24, 8(x2)
    00000574  00050c93  addi x25, x10, 0
    00000578  00058b13  addi x22, x11, 0
    0000057c  86018a93  addi x21, x3, -1952
    00000580  00100b93  addi x23, x0, 1
    00000584  000aa483  lw x9, 0(x21)
    00000588  02048063  beq x9, x0, 32  <__call_exitprocs+0x64>
    0000058c  0044a403  lw x8, 4(x9)
    00000590  0884a983  lw x19, 136(x9)
    00000594  fff40913  addi x18, x8, -1
    00000598  00241413  slli x8, x8, 2
    0000059c  00848a33  add x20, x9, x8
    000005a0  00898433  add x8, x19, x8
    000005a4  02095c63  bge x18, x0, 56  <__call_exitprocs+0x98>
    000005a8  02c12083  lw x1, 44(x2)
    000005ac  02812403  lw x8, 40(x2)
    000005b0  02412483  lw x9, 36(x2)
    000005b4  02012903  lw x18, 32(x2)
    000005b8  01c12983  lw x19, 28(x2)
    000005bc  01812a03  lw x20, 24(x2)
    000005c0  01412a83  lw x21, 20(x2)
    000005c4  01012b03  lw x22, 16(x2)
    000005c8  00c12b83  lw x23, 12(x2)
    000005cc  00812c03  lw x24, 8(x2)
    000005d0  00412c83  lw x25, 4(x2)
    000005d4  03010113  addi x2, x2, 48
    000005d8  00008067  jalr x0, 0(x1)
    000005dc  000b0863  beq x22, x0, 16  <__call_exitprocs+0xa8>
    000005e0  04098663  beq x19, x0, 76  <__call_exitprocs+0xe8>
    000005e4  07c42783  lw x15, 124(x8)
    000005e8  05679263  bne x15, x22, 68  <__call_exitprocs+0xe8>
    000005ec  0044a703  lw x14, 4(x9)
    000005f0  004a2783  lw x15, 4(x20)
    000005f4  fff70713  addi x14, x14, -1
    000005f8  05271263  bne x14, x18, 68  <__call_exitprocs+0xf8>
    000005fc  0124a223  sw x18, 4(x9)
    00000600  02078663  beq x15, x0, 44  <__call_exitprocs+0xe8>
    00000604  1009a683  lw x13, 256(x19)
    00000608  012b9733  sll x14, x23, x18
    0000060c  0044ac03  lw x24, 4(x9)
    00000610  00d776b3  and x13, x14, x13
    00000614  02069863  bne x13, x0, 48  <__call_exitprocs+0x100>
    00000618  000780e7  jalr x1, 0(x15)
    0000061c  0044a783  lw x15, 4(x9)
    00000620  f78792e3  bne x15, x24, -156  <__call_exitprocs+0x40>
    00000624  000aa783  lw x15, 0(x21)
    00000628  f4f49ee3  bne x9, x15, -164  <__call_exitprocs+0x40>
    0000062c  fff90913  addi x18, x18, -1
    00000630  ffca0a13  addi x20, x20, -4
    00000634  ffc40413  addi x8, x8, -4
    00000638  f6dff06f  jal x0, -148  <__call_exitprocs+0x60>
    0000063c  000a2223  sw x0, 4(x20)
    00000640  fc1ff06f  jal x0, -64  <__call_exitprocs+0xbc>
    00000644  1049a683  lw x13, 260(x19)
    00000648  ffc42583  lw x11, -4(x8)
    0000064c  00d77733  and x14, x14, x13
    00000650  00071863  bne x14, x0, 16  <__call_exitprocs+0x11c>
    00000654  000c8513  addi x10, x25, 0
    00000658  000780e7  jalr x1, 0(x15)
    0000065c  fc1ff06f  jal x0, -64  <__call_exitprocs+0xd8>
    00000660  00058513  addi x10, x11, 0
    00000664  000780e7  jalr x1, 0(x15)
    00000668  fb5ff06f  jal x0, -76  <__call_exitprocs+0xd8>
  _write_r:
    0000066c  ff010113  addi x2, x2, -16
    00000670  00812423  sw x8, 8(x2)
    00000674  00050413  addi x8, x10, 0
    00000678  00058513  addi x10, x11, 0
    0000067c  00060593  addi x11, x12, 0
    00000680  00068613  addi x12, x13, 0
    00000684  8601a223  sw x0, -1948(x3)
    00000688  00112623  sw x1, 12(x2)
    0000068c  dadff0ef  jal x1, -596  <_write>
    00000690  fff00793  addi x15, x0, -1
    00000694  00f51863  bne x10, x15, 16  <_write_r+0x38>
    00000698  8641a783  lw x15, -1948(x3)
    0000069c  00078463  beq x15, x0, 8  <_write_r+0x38>
    000006a0  00f42023  sw x15, 0(x8)
    000006a4  00c12083  lw x1, 12(x2)
    000006a8  00812403  lw x8, 8(x2)
    000006ac  01010113  addi x2, x2, 16
    000006b0  00008067  jalr x0, 0(x1)
    000006b4  00000000  .word 0x00000000
    000006b8  00000000  .word 0x00000000
    000006bc  00000000  .word 0x00000000
  crt_section_clear:
    000006c0  02b57063  bgeu x10, x11, 32  <crt_section_clear+0x20>
    000006c4  00b562b3  or x5, x10, x11
    000006c8  0032f293  andi x5, x5, 3
    000006cc  00029e63  bne x5, x0, 28  <crt_section_clear+0x28>
    000006d0  00052023  sw x0, 0(x10)
    000006d4  00450513  addi x10, x10, 4
    000006d8  feb56ce3  bltu x10, x11, -8  <crt_section_clear+0x10>
    000006dc  00008067  jalr x0, 0(x1)
    000006e0  00b51463  bne x10, x11, 8  <crt_section_clear+0x28>
    000006e4  00008067  jalr x0, 0(x1)
    000006e8  00100073  ebreak
  crt_section_copy:
    000006ec  02b57c63  bgeu x10, x11, 56  <crt_section_copy+0x38>
    000006f0  00b562b3  or x5, x10, x11
    000006f4  00c2e2b3  or x5, x5, x12
    000006f8  0032f293  andi x5, x5, 3
    000006fc  02029863  bne x5, x0, 48  <crt_section_copy+0x40>
    00000700  40c502b3  sub x5, x10, x12
    00000704  40a58333  sub x6, x11, x10
    00000708  0262e263  bltu x5, x6, 36  <crt_section_copy+0x40>
    0000070c  00062283  lw x5, 0(x12)
    00000710  00460613  addi x12, x12, 4
    00000714  00552023  sw x5, 0(x10)
    00000718  00450513  addi x10, x10, 4
    0000071c  feb568e3  bltu x10, x11, -16  <crt_section_copy+0x20>
    00000720  00008067  jalr x0, 0(x1)
    00000724  00b51463  bne x10, x11, 8  <crt_section_copy+0x40>
    00000728  00008067  jalr x0, 0(x1)
    0000072c  00100073  ebreak

The vector code of main in rvv_fp.elf, by function, as the same lines of the full listing:

  $ coralview disasm --function main rvv_fp.elf
  main:
    00000144  00000797  auipc x15, 0
    00000148  6547a807  flw f16, 1620(x15)
    0000014c  00000797  auipc x15, 0
    00000150  6547a387  flw f7, 1620(x15)
    00000154  00000797  auipc x15, 0
    00000158  6547a307  flw f6, 1620(x15)
    0000015c  00000797  auipc x15, 0
    00000160  6587a287  flw f5, 1624(x15)
    00000164  00000797  auipc x15, 0
    00000168  6587a207  flw f4, 1624(x15)
    0000016c  00000797  auipc x15, 0
    00000170  6587a187  flw f3, 1624(x15)
    00000174  00000797  auipc x15, 0
    00000178  6207a107  flw f2, 1568(x15)
    0000017c  00000797  auipc x15, 0
    00000180  6207a087  flw f1, 1568(x15)
    00000184  00000797  auipc x15, 0
    00000188  6207a007  flw f0, 1568(x15)
    0000018c  00000797  auipc x15, 0
    00000190  6207a507  flw f10, 1568(x15)
    00000194  00000797  auipc x15, 0
    00000198  61c7a587  flw f11, 1564(x15)
    0000019c  00000797  auipc x15, 0
    000001a0  61c7a607  flw f12, 1564(x15)
    000001a4  00000797  auipc x15, 0
    000001a8  61c7a687  flw f13, 1564(x15)
    000001ac  00000797  auipc x15, 0
    000001b0  61c7a707  flw f14, 1564(x15)
    000001b4  00000797  auipc x15, 0
    000001b8  5dc7a887  flw f17, 1500(x15)
    000001bc  00000797  auipc x15, 0
    000001c0  6107a787  flw f15, 1552(x15)
    000001c4  8e818593  addi x11, x3, -1816
    000001c8  8a818613  addi x12, x3, -1880
    000001cc  0105a227  fsw f16, 4(x11)
    000001d0  0075a427  fsw f7, 8(x11)
    000001d4  0065a627  fsw f6, 12(x11)
    000001d8  0055aa27  fsw f5, 20(x11)
    000001dc  0045ac27  fsw f4, 24(x11)
    000001e0  0035ae27  fsw f3, 28(x11)
    000001e4  00262027  fsw f2, 0(x12)
    000001e8  00162227  fsw f1, 4(x12)
    000001ec  00062427  fsw f0, 8(x12)
    000001f0  00a62627  fsw f10, 12(x12)
    000001f4  00b62827  fsw f11, 16(x12)
    000001f8  00c62a27  fsw f12, 20(x12)
    000001fc  00d62c27  fsw f13, 24(x12)
    00000200  00e62e27  fsw f14, 28(x12)
    00000204  0115a027  fsw f17, 0(x11)
    00000208  0005a823  sw x0, 16(x11)
    0000020c  02f5a027  fsw f15, 32(x11)
    00000210  00000797  auipc x15, 0
    00000214  5c07a807  flw f16, 1472(x15)
    00000218  00000797  auipc x15, 0
    0000021c  5bc7a387  flw f7, 1468(x15)
    00000220  00000797  auipc x15, 0
    00000224  5b87a307  flw f6, 1464(x15)
    00000228  00000797  auipc x15, 0
    0000022c  5b47a287  flw f5, 1460(x15)
    00000230  00000797  auipc x15, 0
    00000234  5b07a207  flw f4, 1456(x15)
    00000238  00000797  auipc x15, 0
    0000023c  5ac7a187  flw f3, 1452(x15)
    00000240  00000797  auipc x15, 0
    00000244  5a87a107  flw f2, 1448(x15)
    00000248  00000797  auipc x15, 0
    0000024c  5a47a087  flw f1, 1444(x15)
    00000250  00000797  auipc x15, 0
    00000254  5a07a007  flw f0, 1440(x15)
    00000258  00000797  auipc x15, 0
    0000025c  59c7a507  flw f10, 1436(x15)
    00000260  00000797  auipc x15, 0
    00000264  5987a587  flw f11, 1432(x15)
    00000268  00000797  auipc x15, 0
    0000026c  5947a607  flw f12, 1428(x15)
    00000270  00000797  auipc x15, 0
    00000274  5907a687  flw f13, 1424(x15)
    00000278  00000797  auipc x15, 0
    0000027c  58c7a707  flw f14, 1420(x15)
    00000280  00000797  auipc x15, 0
    00000284  5887a787  flw f15, 1416(x15)
    00000288  03062027  fsw f16, 32(x12)
    0000028c  0275a227  fsw f7, 36(x11)
    00000290  02662227  fsw f6, 36(x12)
    00000294  0255a427  fsw f5, 40(x11)
    00000298  02462427  fsw f4, 40(x12)
    0000029c  0235a627  fsw f3, 44(x11)
    000002a0  02262627  fsw f2, 44(x12)
    000002a4  0215a827  fsw f1, 48(x11)
    000002a8  02062827  fsw f0, 48(x12)
    000002ac  02a5aa27  fsw f10, 52(x11)
    000002b0  02b62a27  fsw f11, 52(x12)
    000002b4  02c5ac27  fsw f12, 56(x11)
    000002b8  02d62c27  fsw f13, 56(x12)
    000002bc  02e5ae27  fsw f14, 60(x11)
    000002c0  02f62e27  fsw f15, 60(x12)
    000002c4  00000693  addi x13, x0, 0
    000002c8  86818513  addi x10, x3, -1944
    000002cc  01000e13  addi x28, x0, 16
    000002d0  00f00313  addi x6, x0, 15
    000002d4  00269713  slli x14, x13, 2
    000002d8  40de07b3  sub x15, x28, x13
    000002dc  0d07f7d7  vsetvli x15, x15, e32, m1, ta, ma
    000002e0  00e588b3  add x17, x11, x14
    000002e4  00e60833  add x16, x12, x14
    000002e8  0208e087  vle32.v v1, 0(x17)
    000002ec  02086107  vle32.v v2, 0(x16)
    000002f0  00e50733  add x14, x10, x14
    000002f4  00f686b3  add x13, x13, x15
    000002f8  021110d7  vfadd.vv v1, v1, v2
    000002fc  020760a7  vse32.v v1, 0(x14)
    00000300  fcd37ae3  bgeu x6, x13, -44  <main+0x190>
    00000304  00000797  auipc x15, 0
    00000308  5087a787  flw f15, 1288(x15)
    0000030c  00052707  flw f14, 0(x10)
    00000310  a0f727d3  feq.s x15, f14, f15
    00000314  14078863  beq x15, x0, 336  <main+0x320>
    00000318  00000797  auipc x15, 0
    0000031c  4f87a787  flw f15, 1272(x15)
    00000320  00452707  flw f14, 4(x10)
    00000324  a0f727d3  feq.s x15, f14, f15
    00000328  12078e63  beq x15, x0, 316  <main+0x320>
    0000032c  00000797  auipc x15, 0
    00000330  4e87a787  flw f15, 1256(x15)
    00000334  00852707  flw f14, 8(x10)
    00000338  a0f727d3  feq.s x15, f14, f15
    0000033c  12078463  beq x15, x0, 296  <main+0x320>
    00000340  00000797  auipc x15, 0
    00000344  4d87a787  flw f15, 1240(x15)
    00000348  00c52707  flw f14, 12(x10)
    0000034c  a0f727d3  feq.s x15, f14, f15
    00000350  10078a63  beq x15, x0, 276  <main+0x320>
    00000354  00000797  auipc x15, 0
    00000358  45c7a787  flw f15, 1116(x15)
    0000035c  01052707  flw f14, 16(x10)
    00000360  a0f727d3  feq.s x15, f14, f15
    00000364  10078063  beq x15, x0, 256  <main+0x320>
    00000368  00000797  auipc x15, 0
    0000036c  4b47a787  flw f15, 1204(x15)
    00000370  01452707  flw f14, 20(x10)
    00000374  a0f727d3  feq.s x15, f14, f15
    00000378  0e078663  beq x15, x0, 236  <main+0x320>
    0000037c  00000797  auipc x15, 0
    00000380  4a47a787  flw f15, 1188(x15)
    00000384  01852707  flw f14, 24(x10)
    00000388  a0f727d3  feq.s x15, f14, f15
    0000038c  0c078c63  beq x15, x0, 216  <main+0x320>
    00000390  00000797  auipc x15, 0
    00000394  4947a787  flw f15, 1172(x15)
    00000398  01c52707  flw f14, 28(x10)
    0000039c  a0f727d3  feq.s x15, f14, f15
    000003a0  0c078263  beq x15, x0, 196  <main+0x320>
    000003a4  00000797  auipc x15, 0
    000003a8  4347a787  flw f15, 1076(x15)
    000003ac  02052707  flw f14, 32(x10)
    000003b0  a0f727d3  feq.s x15, f14, f15
    000003b4  0a078863  beq x15, x0, 176  <main+0x320>
    000003b8  00000797  auipc x15, 0
    000003bc  4707a787  flw f15, 1136(x15)
    000003c0  02452707  flw f14, 36(x10)
    000003c4  a0f727d3  feq.s x15, f14, f15
    000003c8  08078e63  beq x15, x0, 156  <main+0x320>
    000003cc  00000797  auipc x15, 0
    000003d0  4607a787  flw f15, 1120(x15)
    000003d4  02852707  flw f14, 40(x10)
    000003d8  a0f727d3  feq.s x15, f14, f15
    000003dc  08078463  beq x15, x0, 136  <main+0x320>
    000003e0  00000797  auipc x15, 0
    000003e4  4507a787  flw f15, 1104(x15)
    000003e8  02c52707  flw f14, 44(x10)
    000003ec  a0f727d3  feq.s x15, f14, f15
    000003f0  06078a63  beq x15, x0, 116  <main+0x320>
    000003f4  00000797  auipc x15, 0
    000003f8  40c7a787  flw f15, 1036(x15)
    000003fc  03052707  flw f14, 48(x10)
    00000400  a0f727d3  feq.s x15, f14, f15
    00000404  06078063  beq x15, x0, 96  <main+0x320>
    00000408  00000797  auipc x15, 0
    0000040c  42c7a787  flw f15, 1068(x15)
    00000410  03452707  flw f14, 52(x10)
    00000414  a0f727d3  feq.s x15, f14, f15
    00000418  04078663  beq x15, x0, 76  <main+0x320>
    0000041c  00000797  auipc x15, 0
    00000420  41c7a787  flw f15, 1052(x15)
    00000424  03852707  flw f14, 56(x10)
    00000428  a0f727d3  feq.s x15, f14, f15
    0000042c  02078c63  beq x15, x0, 56  <main+0x320>
    00000430  00000797  auipc x15, 0
    00000434  40c7a787  flw f15, 1036(x15)
    00000438  03c52707  flw f14, 60(x10)
    0000043c  a0f727d3  feq.s x15, f14, f15
    00000440  02078263  beq x15, x0, 36  <main+0x320>
    00000444  00000797  auipc x15, 0
    00000448  3807a787  flw f15, 896(x15)
    0000044c  4487f053  fcvt.bf16.s f0, f15
    00000450  e0000753  fmv.x.w x14, f0
    00000454  000047b7  lui x15, 4
    00000458  08074733  pack x14, x14, x0
    0000045c  fc078793  addi x15, x15, -64
    00000460  00f70663  beq x14, x15, 12  <main+0x328>
    00000464  00100513  addi x10, x0, 1
    00000468  00008067  jalr x0, 0(x1)
    0000046c  ff010113  addi x2, x2, -16
    00000470  01200613  addi x12, x0, 18
    00000474  00000597  auipc x11, 0
    00000478  3cc58593  addi x11, x11, 972
    0000047c  00100513  addi x10, x0, 1
    00000480  00112623  sw x1, 12(x2)
    00000484  110000ef  jal x1, 272  <write>
    00000488  00c12083  lw x1, 12(x2)
    0000048c  00000513  addi x10, x0, 0
    00000490  01010113  addi x2, x2, 16
    00000494  00008067  jalr x0, 0(x1)

`--no-padding` prints each run of zero words once; everything else is the listing above:

  $ coralview disasm matrix.elf > full.txt
  $ coralview disasm --no-padding matrix.elf > packed.txt
  $ diff full.txt packed.txt
  445,447c445
  <   000006b4  00000000  .word 0x00000000
  <   000006b8  00000000  .word 0x00000000
  <   000006bc  00000000  .word 0x00000000
  ---
  >   000006b4  3 zero words (12 bytes)
  [1]
  $ coralview disasm --no-padding --format jsonl matrix.elf | grep padding
  {"padding_words":3,"address":1716}

`--summary` counts the instructions of each function by class; a `.word` is `data`:

  $ coralview disasm --summary matrix.elf
  _start: 81 instructions, alu 55, branch 12, mem 4, system 10
  main: 187 instructions, alu 78, branch 33, fp 8, mem 29, system 4, tile 25, vector-mem 10
  coralnpu_exception_handler: 2 instructions, branch 1, system 1
  _write: 58 instructions, alu 21, branch 4, mem 30, system 3
  __cxa_finalize: 3 instructions, alu 2, branch 1
  write: 6 instructions, alu 4, branch 1, mem 1
  __call_exitprocs: 74 instructions, alu 19, branch 19, mem 36
  _write_r: 21 instructions, alu 7, branch 4, data 3, mem 7
  crt_section_clear: 11 instructions, alu 3, branch 6, mem 1, system 1
  crt_section_copy: 17 instructions, alu 7, branch 7, mem 2, system 1
  $ coralview disasm --summary --function main matrix.elf
  main: 187 instructions, alu 78, branch 33, fp 8, mem 29, system 4, tile 25, vector-mem 10
  $ coralview disasm --summary --format jsonl matrix.elf
  --summary prints text only
  [2]
