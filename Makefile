OPAM_EXEC = opam exec --
DUNE = $(OPAM_EXEC) dune
CORALNPU ?= /opt/coralnpu
export RIVET_EXTERNAL_DEPS = true

.PHONY: deps versions build test fmt fmt-check hwfrp-boundary smoke zvt-check ci clean

deps:
	opam install . --deps-only --with-test -y

versions:
	$(OPAM_EXEC) ocamlfind ocamlopt -version
	$(DUNE) --version
	opam list --columns=name,version,pin ovcd fst unlz4 err_trace ocamlformat
	cat $(CORALNPU)/RELEASE

build:
	$(DUNE) build

test:
	$(DUNE) build @runtest

fmt:
	$(DUNE) build @fmt --auto-promote

fmt-check:
	$(DUNE) build @fmt

# hwfrp builds and tests as a package of its own, and its libraries use ovcd
# and unix only (its tests add qcheck and ppx_expect): no Rivet, jsont or Coral.
HWFRP_DEPS = hwfrp ovcd ovcd.fst ovcd.vcd_types ovcd.vcd_filter unix qcheck-core ppx_expect

hwfrp-boundary:
	$(DUNE) build --build-dir $(CURDIR)/_build/hwfrp -p hwfrp @install @hwfrp/runtest
	deps=$$($(DUNE) describe external-lib-deps \
	  | awk '/\(source_dir /{h = $$0 ~ /source_dir hwfrp\//; d = 0} h && /_deps/{d = 1} h && d' \
	  | grep -o '([a-z][a-z0-9_.-]* required' | cut -c2- | cut -d' ' -f1 | sort -u); \
	test -n "$$deps"; \
	bad=$$(for d in $$deps; do case " $(HWFRP_DEPS) " in *" $$d "*) ;; *) echo $$d ;; esac; done); \
	if [ -n "$$bad" ]; then echo "hwfrp must not depend on:" $$bad; exit 1; fi

VME_MODELS = commits stalls memory axi registers tiles traps vectors

# RTL simulations with tracing, read back by coralview: every model on the VME
# core, the external traffic of memory.elf on the scalar core, and the DMA jobs
# of subsystem_dma.elf on the full subsystem. Each JSONL rendered back must give
# the text: on the VME trace for every model, in one pass.
smoke: build
	set -e; d=$$(mktemp -d); trap 'rm -rf $$d' EXIT; \
	timeout --kill-after=5 300 $(CORALNPU)/emulators/bin/vme_core_mini_axi_sim \
	  --cycles=1000000 --trace --binary=$(CORALNPU)/emulators/examples/matrix.elf > $$d/log 2>&1; \
	grep -q CORAL_MATRIX_PASS $$d/log; \
	fst=$$(sed -n 's/.*for tracing: 1 ps (\(.*\.fst\)).*/\1/p' $$d/log); \
	ls -l $$fst; \
	$(DUNE) exec -- coralview probe $$fst; \
	p="--platform vme-core-mini-axi"; \
	$(DUNE) exec -- coralview platforms --manifest $(CORALNPU)/emulators/hardware-configurations.json \
	  --manifest $(CORALNPU)/subsystem/hardware-configurations.json; \
	$(DUNE) exec -- coralview check $$p $$fst; \
	$(DUNE) exec -- coralview commits $$p --limit 20 --profile 10 $$fst; \
	$(DUNE) exec -- coralview stalls $$p --profile 10 $$fst; \
	$(DUNE) exec -- coralview memory $$p --manifest $(CORALNPU)/emulators/hardware-configurations.json --limit 10 $$fst; \
	$(DUNE) exec -- coralview tiles $$p --limit 10 $$fst; \
	$(DUNE) exec -- coralview registers $$p --at 600 $$fst; \
	$(DUNE) exec -- coralview vectors $$p --limit 5 $$fst; \
	$(DUNE) exec -- coralview traps $$p $$fst; \
	$(DUNE) exec -- coralview signals $$p --changes --to-cycle 600 $$fst VVmeCoreMiniAxi.core/VmeCoreMiniAxi/io_halted; \
	$(DUNE) exec -- coralview axi $$p --limit 5 $$fst; \
	$(DUNE) exec -- coralview bench $$p $$fst; \
	$(DUNE) exec -- coralview run $$p \
	  $(foreach m,$(VME_MODELS),--sink $(m):text:$$d/$(m).txt --sink $(m):jsonl:$$d/$(m).jsonl) $$fst; \
	for m in $(VME_MODELS); do $(DUNE) exec -- coralview render $$d/$$m.jsonl | cmp - $$d/$$m.txt; done
	set -e; d=$$(mktemp -d); trap 'rm -rf $$d' EXIT; \
	timeout --kill-after=5 300 $(CORALNPU)/emulators/bin/core_mini_axi_sim \
	  --cycles=5000000 --trace --binary=$(CORALNPU)/emulators/examples/memory.elf > $$d/log 2>&1; \
	grep -q CORAL_MEMORY_PASS $$d/log; \
	fst=$$(sed -n 's/.*for tracing: 1 ps (\(.*\.fst\)).*/\1/p' $$d/log); \
	$(DUNE) exec -- coralview axi --platform core-mini-axi --limit 5 --profile 5 $$fst | tee $$d/axi; \
	grep -q ' unmatched 0$$' $$d/axi; \
	! grep -q DISAGREEING $$d/axi; \
	$(DUNE) exec -- coralview axi --platform core-mini-axi --format jsonl $$fst > $$d/axi.jsonl; \
	$(DUNE) exec -- coralview render --limit 5 --profile 5 $$d/axi.jsonl | cmp - $$d/axi
	set -e; d=$$(mktemp -d); trap 'rm -rf $$d' EXIT; \
	s=$(CORALNPU)/subsystem; \
	tools/trace-subsystem.sh $$s vector_normal $$s/examples/subsystem_dma.elf 8 32 $$d | grep -q CORAL_SUBSYSTEM_DMA_PASS; \
	$(DUNE) exec -- coralview dma --platform subsystem-vector-normal --manifest $$s/hardware-configurations.json \
	  --beats 2 $$d/sim.fst | tee $$d/dma; \
	grep -q ': jobs 3, 192 bytes .* 0 stray$$' $$d/dma; \
	test $$(grep -c 'software saw done' $$d/dma) = 3; \
	$(DUNE) exec -- coralview dma --platform subsystem-vector-normal --manifest $$s/hardware-configurations.json \
	  --format jsonl $$d/sim.fst > $$d/dma.jsonl; \
	$(DUNE) exec -- coralview render --manifest $$s/hardware-configurations.json --beats 2 $$d/dma.jsonl | cmp - $$d/dma

# The committed Zvt table must be the one the image's emulator archive ships.
zvt-check:
	if [ -e $(CORALNPU)/emulators/isa/zvt.jsonl ]; then \
	  cmp src/riscv/zvt.jsonl $(CORALNPU)/emulators/isa/zvt.jsonl; \
	else \
	  echo "release $$(cat $(CORALNPU)/RELEASE) has no isa/zvt.jsonl; not compared"; \
	fi

ci: fmt-check build test hwfrp-boundary zvt-check smoke

clean:
	$(DUNE) clean
