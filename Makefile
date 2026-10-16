OPAM_EXEC = opam exec --
DUNE = $(OPAM_EXEC) dune
CORALNPU ?= /opt/coralnpu
export RIVET_EXTERNAL_DEPS = true

.PHONY: deps versions build test fmt fmt-check smoke ci clean

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

# One RTL simulation with tracing, read back by coralview.
smoke: build
	set -e; d=$$(mktemp -d); trap 'rm -rf $$d' EXIT; \
	timeout --kill-after=5 300 $(CORALNPU)/emulators/bin/vme_core_mini_axi_sim \
	  --cycles=1000000 --trace --binary=$(CORALNPU)/emulators/examples/matrix.elf > $$d/log 2>&1; \
	grep -q CORAL_MATRIX_PASS $$d/log; \
	fst=$$(sed -n 's/.*for tracing: 1 ps (\(.*\.fst\)).*/\1/p' $$d/log); \
	ls -l $$fst; \
	$(DUNE) exec -- coralview probe $$fst

ci: fmt-check build test smoke

clean:
	$(DUNE) clean
