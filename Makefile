OPAM_EXEC = opam exec --
DUNE = $(OPAM_EXEC) dune
CORALNPU ?= /opt/coralnpu
export RIVET_EXTERNAL_DEPS = true

.PHONY: deps versions build test fmt fmt-check hwfrp-boundary isa-check rivet-pin-check smoke zvt-check integration ci clean

# rivet is a dependency of the package, for installs from opam. In this tree dune builds the vendored copy,
# and an installed one next to it makes dune fail with "rivet.fmt is already defined".
deps:
	opam install . --deps-only --with-test -y
	if opam list --installed --silent rivet; then opam remove -y rivet; fi

versions:
	$(OPAM_EXEC) ocamlfind ocamlopt -version
	$(DUNE) --version
	opam list --columns=name,version,pin ovcd fst unlz4 err_trace elf ocamlformat
	cat $(CORALNPU)/RELEASE

build:
	$(DUNE) build

test:
	$(DUNE) build @runtest

fmt:
	$(DUNE) build @fmt --auto-promote

fmt-check:
	$(DUNE) build @fmt

# hwfrp builds and tests as a package of its own: no Rivet, jsont or Coral. Its core library
# (hwfrp/src) reads no waveform and uses ovcd's types only; VCD text is hwfrp/vcd, and files, FST
# and the wall clock are hwfrp/native, the only places that may use ovcd.fst and unix.
HWFRP_ALLOWED = hwfrp/src=ovcd ovcd.vcd_types ovcd.vcd_filter;hwfrp/vcd=ovcd ovcd.vcd_types;hwfrp/native=ovcd ovcd.fst ovcd.vcd_types unix;hwfrp/sinks=;hwfrp/test=ovcd ovcd.vcd_types ovcd.vcd_filter qcheck-core ppx_expect

hwfrp-boundary:
	$(DUNE) build --build-dir $(CURDIR)/_build/hwfrp -p hwfrp @install @hwfrp/runtest
	$(DUNE) describe external-lib-deps | awk -v allowed='$(HWFRP_ALLOWED)' ' \
	  BEGIN { n = split(allowed, a, ";"); for (i = 1; i <= n; i++) { split(a[i], kv, "="); ok[kv[1]] = " " kv[2] " " } } \
	  /\(source_dir /{ dir = $$2; sub(/\)+$$/, "", dir); ext = 0 } \
	  /\(external_deps/{ ext = 1 } \
	  /\(internal_deps/{ ext = 0 } \
	  ext && (dir in ok) && match($$0, /\([a-z][a-z0-9_.-]* required/) { \
	    name = substr($$0, RSTART + 1, RLENGTH - 10); seen[dir] = 1; \
	    if (index(ok[dir], " " name " ") == 0) { print dir " must not depend on " name; bad = 1 } } \
	  END { for (d in ok) if (!(d in seen) && ok[d] != "  ") { print d ": no dependencies found"; bad = 1 } exit bad }'

# Zvt words decode and assemble back to themselves; the same program runs against the opam install.
isa-check:
	$(DUNE) exec -- coral-isa-check

VME_MODELS = commits stalls memory axi registers tiles ops traps vectors

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
	$(DUNE) exec -- coralview commits $$p $$fst > $$d/commits.txt; \
	grep -q ' mpause ' $$d/commits.txt; \
	test "$$(grep -c '\.word' $$d/commits.txt)" = 0; \
	$(DUNE) exec -- coralview commits $$p --elf $(CORALNPU)/emulators/examples/matrix.elf --around-symbol main \
	  --limit 0 --profile 5 --profile-by function $$fst | tee $$d/main.txt; \
	grep -q '^window \[' $$d/main.txt; \
	grep -q '^main ' $$d/main.txt; \
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
	$(DUNE) exec -- coralview render --limit 5 --profile 5 $$d/axi.jsonl | cmp - $$d/axi; \
	$(DUNE) exec -- coralview cost --platform core-mini-axi --manifest $(CORALNPU)/emulators/hardware-configurations.json $$fst | tee $$d/cost; \
	grep -q '^mem  *dtcm ' $$d/cost; \
	grep -q '^mem  *testbench-ram ' $$d/cost
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

# vendor/rivet and the opam pin-depends must name one Rivet commit.
rivet-pin-check:
	vendored=$$(git rev-parse :vendor/rivet); \
	for f in coralview.opam coral-isa.opam coralview.opam.template coral-isa.opam.template; do \
	  grep -q "TheCBaH/rivet.git#$$vendored" $$f || { echo "$$f: rivet pin differs from vendor/rivet $$vendored"; exit 1; }; \
	done

# The committed Zvt table must be the one the image's emulator archive ships.
zvt-check:
	if [ -e $(CORALNPU)/emulators/isa/zvt.jsonl ]; then \
	  cmp isa/zvt.jsonl $(CORALNPU)/emulators/isa/zvt.jsonl; \
	else \
	  echo "release $$(cat $(CORALNPU)/RELEASE) has no isa/zvt.jsonl; not compared"; \
	fi

# Plan, selection and live VCD against the archive's simulators (skipped for a release without them).
integration: build
	for mode in selection stream selected-stream; do \
	  tools/integration.sh $$mode $$(pwd)/_build/default/bin/coralview.exe $(CORALNPU) || exit 1; \
	done

ci: fmt-check build test hwfrp-boundary rivet-pin-check isa-check zvt-check smoke integration

clean:
	$(DUNE) clean
