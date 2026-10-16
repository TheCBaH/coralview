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
  ovcd
  fst
  err_trace
  fmt
  menhir))
