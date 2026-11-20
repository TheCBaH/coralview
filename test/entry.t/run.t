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

The help says the same:

  $ coralview commits --help=plain | tr '\n' ' ' | tr -s ' ' | grep -o -- '--entry=NAME.*not counted'
  --entry=NAME Print rows from the first retirement of the entry of function NAME of the --elf to the ret that pops its frame (calls inside it nest), or to the end of the trace if there is none: the startup before it is not counted
  $ coralview compare --help=plain | tr '\n' ' ' | tr -s ' ' | grep -o -- '--entry=NA.\{0,150\}' | sed 's/ --format.*//'
  --entry=NA[,NB] As --around-symbol, but to the ret that pops the entry's frame (calls inside it nest), or to the end of that trace if there is none.

A negative --top is refused before either trace is read, whatever else is asked of the comparison:

  $ coralview compare --platform entry-core.json --elf entry.elf --entry kernel --top=-1 --loops entry.vcd entry.vcd > out.txt 2>&1; echo $?
  124
  $ tail -n 1 out.txt
  coralview: option '--top': -1 is negative; expected N >= 0
  $ grep '^platform' out.txt
  [1]
