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
  ovcd
  fst
  err_trace
  fmt
  menhir))

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
