A trace that lacks a signal of each of two models (two.vcd, made by gen.sh, has no written value for commits and
no fault PC for memory). Every missing signal is reported, and the status is the failure's, 3:

  $ coralview check --platform two-core.json two.vcd > out.txt 2> err.txt
  [3]
  $ grep -v '^  *bound' out.txt err.txt
  out.txt:platform two-core
  out.txt:commits at TOP.core
  out.txt:  missing io_debug_regfile_writeData_0_bits_data: written value
  out.txt:memory at TOP.core
  out.txt:memory at TOP.core.lsu.slot
  out.txt:memory at TOP.core.lsu
  out.txt:  missing io_fault_bits_epc
  err.txt:platform two-core does not match the trace: 2 of 29 signals failed

  $ coralview check --platform two-core.json --format jsonl two.vcd > out.txt 2> err.txt
  [3]
  $ grep -v '"status":"bound"' out.txt
  {"type":"coralview","schema_version":3,"model":"check","platform":"two-core","trace":"two.vcd"}
  {"type":"check.binding","model":"commits","root":"TOP.core","path":"io_debug_regfile_writeData_0_bits_data","width":"<=62","purpose":"written value","status":"missing"}
  {"type":"check.binding","model":"memory","root":"TOP.core.lsu","path":"io_fault_bits_epc","width":"<=62","status":"missing"}
  {"type":"check.summary","bound":27,"failed":2}

A clock that is not in the trace is reported with the other signals of the model:

  $ coralview check --platform noclk-core.json --model commits two.vcd > out.txt 2> err.txt
  [3]
  $ grep -v '^  *bound' out.txt err.txt
  out.txt:platform noclk-core
  out.txt:commits at TOP.core
  out.txt:  missing io_clk: core clock
  out.txt:  missing io_debug_regfile_writeData_0_bits_data: written value
  err.txt:platform noclk-core does not match the trace: 2 of 11 signals failed
