# coralview

[![ci](https://github.com/TheCBaH/coralview/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/TheCBaH/coralview/actions/workflows/ci.yml)

* [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=1422260077)

Observability for the [Coral NPU](https://github.com/google-coral/coralnpu)
RTL simulators. coralview reads their VCD and FST traces with
[ovcd](https://github.com/TheCBaH/ovcd), binds the signals a JSON platform
description names, and runs models over them: what each instruction did and
how long it took, why dispatch stalled, memory and AXI traffic, DMA jobs,
the register files, traps, and vector operations per cycle. Instructions
are decoded with [Rivet](https://github.com/TheCBaH/rivet), including
Coral's Zvt matrix extension.

The models are graphs of [hwfrp](hwfrp/README.md), a synchronous dataflow
engine over traces that depends only on ovcd and is built as its own
package. Every model writes text or JSON lines; `coralview run` builds
several in one pass and also writes Perfetto traces, Kanata logs and a
Markdown report.

## Get started

The devcontainer has OCaml, the dependencies and the Coral NPU simulators
under `/opt/coralnpu`; open it in a Codespace or with the devcontainer CLI.

```
make deps   # install the opam dependencies
make        # build
make test   # unit and cram tests
make smoke  # run the simulators with tracing and every model on the traces
make ci     # what CI runs
```

```
$ e=/opt/coralnpu/emulators
$ $e/bin/rvv_core_mini_highmem_axi_sim --trace --binary=$e/examples/rvv_matmul_fp32.elf
$ coralview platforms --manifest $e/hardware-configurations.json
$ coralview ops --platform rvv-core-mini-highmem-axi /tmp/VRvvCoreMiniHighmemAxi.core.fst
$ coralview run --platform rvv-core-mini-highmem-axi --model commits --model stalls \
    --perfetto trace.json /tmp/VRvvCoreMiniHighmemAxi.core.fst
```

## Scripted runs

The simulators write their FST to a fixed path (`/tmp/V<Top>.core.fst` with `--trace`), so two runs of
one core at once overwrite each other. Choose the path with `--trace_file=PATH`, or skip the file: the
VCD simulators (`*_vcd_sim`) write the trace to a descriptor, and `--exec` gives them descriptor 3 and
reads it as it is produced (the trace argument is `-`):

```
$ e=/opt/coralnpu/emulators
$ coralview commits --platform core-mini-axi --elf $e/examples/exit_status.elf \
    --exec "$e/bin/core_mini_axi_vcd_sim --trace_fd=3 --binary=$e/examples/exit_status.elf" -
$ $e/bin/core_mini_axi_sim --trace_file=run1.fst --binary=$e/examples/exit_status.elf
$ coralview cost --platform core-mini-axi --manifest $e/hardware-configurations.json \
    --elf $e/examples/exit_status.elf --entry main run1.fst
```

A command that reads the trace twice (`cost`, and anything with `--between-pc`, `--around-symbol` or
`--entry`) needs a file. The simulator's own exit status (here 125, the program's) is reported after
the results as `# producer: failed, exited with status N`; coralview exits 4 for it.

## Installing

`make deps` is what the devcontainer runs. To install the package elsewhere, `opam install
./coralview.opam` takes Rivet from the commit its `pin-depends` names and replaces a Rivet you have
pinned to a path; install coralview first and pin your own Rivet afterwards (`opam pin rivet.dev
PATH`). opam writes into the switch, so the switch must be one your user owns. In a checkout dune
builds `vendor/rivet`, and an installed `rivet` next to it makes dune fail with `rivet.fmt is already
defined`: `make deps` removes it.

## Commands

* Traces: `probe`, `tree`, `signals`, `decode`, `platforms`, `check`, `bench`.
* Code: `disasm` lists the code of an RV32 ELF with Rivet (Zvt included), labelled by its
  symbols, with `jal`/branch targets as `<symbol+off>`; `--section`, `--function`, `--range`
  and `--format text|jsonl`. A word Rivet has no form for prints as `.word`; an ELF that
  marks compressed instructions is refused. `--no-padding` prints each run of zero words
  once; `--summary` counts instructions by class per function; `--vconfig` notes each vector
  instruction's SEW, LMUL and AVL from the `vsetvli` words that reach it (`vtype unknown` where none does). `commits --vector` adds the SEW, LMUL and `vl` the RVV backend ran
  each vector instruction under, and flags a difference from the static one.
* Models: `commits`, `stalls`, `memory`, `axi`, `dma`, `tiles`, `ops`,
  `registers`, `vectors`, `traps`, each with `--format text|jsonl`.
* Loops: `loops` finds loops from backward branches and prints trips, instructions and cycles a trip
  (median, range) and each PC's mean cycles over the trips; it takes the windows of the other commands.
* `summary` gives the figures of a window (instructions, cycles, data requests, vector operations,
  stall reasons) as text or one JSONL record.
* `compare` puts two runs of one kernel side by side: both windows' summaries and the instructions whose
  cycles differ most, matched by offset from the function's entry.
* Several models and sinks: `run`; saved JSON lines: `render`, `profile`.

## Documentation

* [doc/coralnpu.md](doc/coralnpu.md): the platforms, the blocks each model
  observes, the models, the output formats and the JSONL schema.
* [hwfrp/README.md](hwfrp/README.md): the engine.

## License

MIT; see [LICENSE](LICENSE).
