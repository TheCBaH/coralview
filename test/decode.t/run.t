Scalar and vector words decode with Rivet's standard tables:

  $ coralview decode 02a00513 0d05f557 022180d7 02056087 b22550d7
  02a00513  addi x10, x0, 42
  0d05f557  vsetvli x10, x11, e32, m1, ta, ma
  022180d7  vadd.vv v1, v2, v3
  02056087  vle32.v v1, 0(x10)
  b22550d7  vfmacc.vf v1, f10, v2

Coral's Zvt words, taken from the release matrix.elf, decode with the rows
exported from MPACT; Coral's msetmtype and msettn differ from the
riscv-opcodes draft:

  $ coralview decode 82b6f057 840675d7 43e06057 52c17027 f28800f7 f2881077 f28810f7
  82b6f057  msetmtype x0, x13, x11
  840675d7  msettn x11, x12
  43e06057  vtzero mt0
  52c17027  vtse32 x12, 0(x2)
  f28800f7  vtmms.tvv mt0, v8, v16
  f2881077  vtfmm.tvv mt0, v8, v16
  f28810f7  vtfmm.alt.tvv mt0, v8, v16

The Zvt rows are off without xcoralzvt, and the 64-bit tile loads, which
the RTL traps on, are not decoded:

  $ coralview decode --features none,+m,+zve32x 43e06057
  43e06057  error: <synthesized by riscv32>: error[riscv32.feature]: vtzero requires feature xcoralzvt, which is not enabled
  $ coralview decode 72007007
  72007007  error: <synthesized by riscv32>: error[riscv32.decode]: no form matches this word

The remaining forms, with words from coralnpu's VME cocotb tests:

  $ coralview decode 841776d7 842877d7 8431f057 43fa6257 5e456057 12b57007 43c06057 f2040077
  841776d7  msettm x13, x14
  842877d7  msettk x15, x16
  8431f057  msetmtypei x0, 3, 0
  43fa6257  vtmv.v.t v4, x20
  5e456057  vtmv.t.v x10, v4
  12b57007  vtle8 x11, 0(x10)
  43c06057  vtdiscard
  f2040077  vtmmu.tvv mt0, v0, v8
