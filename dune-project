(lang dune 3.21)

(name coralview)

(generate_opam_files true)

(license MIT)

(authors "Vladimir Silyaev")

(maintainers "Vladimir Silyaev")

(source
 (github TheCBaH/coralview))

(package
 (name coralview)
 (synopsis "Coral NPU tooling: simulator runner and trace observability")
 (description
  "Runs the Coral NPU simulators, reads their FST waveforms with ovcd and decodes the executed instructions with Rivet.")
 (depends
  (ocaml
   (>= 4.14))
  hwfrp
  coral-isa
  ovcd
  fst
  err_trace
  rivet
  fmt
  menhir
  (jsont
   (>= 0.4.0))
  bytesrw
  (cmdliner
   (>= 1.1.0))))

(package
 (name hwfrp)
 (synopsis "Functional reactive models of hardware over waveform traces")
 (description
  "A synchronous dataflow engine that samples VCD and FST waveforms, read with ovcd, per clock domain and evaluates signal, event and state-machine graphs over them.")
 (depends
  (ocaml
   (>= 4.14))
  ovcd
  (ppx_expect :with-test)
  (qcheck-core :with-test)))

(package
 (name coral-isa)
 (synopsis "Coral NPU's Zvt matrix instructions for Rivet")
 (description
  "Coral NPU's Zvt (VME) instructions as a Rivet vendor extension: RV32 disassembly and assembly with the matrix instructions, built from the encodings exported from Coral's MPACT decoder, and a round-trip check.")
 (depends
  (ocaml
   (>= 4.14))
  rivet
  (jsont
   (>= 0.4.0))
  bytesrw))
