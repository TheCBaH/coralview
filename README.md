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

## Commands

* Traces: `probe`, `tree`, `signals`, `decode`, `platforms`, `check`, `bench`.
* Models: `commits`, `stalls`, `memory`, `axi`, `dma`, `tiles`, `ops`,
  `registers`, `vectors`, `traps`, each with `--format text|jsonl`.
* Several models and sinks: `run`; saved JSON lines: `render`, `profile`.

## Documentation

* [doc/coralnpu.md](doc/coralnpu.md): the platforms, the blocks each model
  observes, the models, the output formats and the JSONL schema.
* [hwfrp/README.md](hwfrp/README.md): the engine.

## License

MIT; see [LICENSE](LICENSE).
