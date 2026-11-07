A kernel that calls a helper, with code after the kernel: `addi`; `kernel`, which has an `addi`,
`jal x1` into `helper` (an `addi` and its `ret`), an `addi` and its own `ret`; then an `addi` of the caller.

  $ ../../tools/mkelf.exe entry.elf 80000000 startup:4 kernel:16 helper:8 pad:4 after:4

`--entry` runs from the function's entry to the `ret` that pops its frame, so the helper's `ret` does not end
the window and the caller's code does not enter it:

  $ coralview summary --platform entry-core.json --elf entry.elf --entry kernel entry.vcd
  platform entry-core
  window [10, 15]
    instructions 6, cycles charged 6
  $ coralview summary --platform entry-core.json --elf entry.elf --entry helper entry.vcd
  platform entry-core
  window [12, 13]
    instructions 2, cycles charged 2

A function that never returns runs to the end of the trace:

  $ coralview summary --platform entry-core.json --elf entry.elf --entry after entry.vcd
  platform entry-core
  window [16, end]
    instructions 1, cycles charged 1
