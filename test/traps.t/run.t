A store at 0x10 faults in cycle 2; the CSRs take its cause, PC and address
in cycle 3, when it retires as a trap, and the handler at mtvec (0x41, mode
bits cleared) is dispatched in cycle 4 and retires in cycle 5. Software
then writes mepc, which is no fault. A load at 0x20 retires in cycle 7,
before its fault arrives in cycle 8; the CSRs are updated and the handler
dispatched, but it never retires, so the trap is not delivered:

  $ coralview traps --platform trap-core.json traps.vcd
         2 store fault: cause 7 (store access fault), pc 00000010, mtval 00000100
           csr      mcause/mepc/mtval hold them at 3
           pc       retired up to the fault never, after it at 3 as a trap
           handler  00000040 dispatched at 4, retired at 5: delivered
         6 csr change with no fault: mcause 7 (store access fault), mepc 00000014, mtval 00000100
         8 load fault: cause 5 (load access fault), pc 00000020, mtval 00003000
           csr      mcause/mepc/mtval hold them at 9
           pc       retired up to the fault at 7, after it never
           handler  00000040 dispatched at 10, retired never: not delivered by cycle 12
  root TOP.core: 13 cycles, 2 faults, 1 delivered

Without the CSR registers the description does not match the trace:

As JSON lines, each fault once its record ends, and the CSR changes as they come:

  $ coralview traps --platform trap-core.json --format jsonl traps.vcd | jq -c 'select(.type != "coralview")'
  {"type":"traps.csr_change","cycle":6,"mcause":7,"mepc":20,"mtval":256}
  {"type":"traps.fault","cycle":2,"source":"store","pc":16,"cause":7,"value":256,"handler":64,"csr":3,"retired_after":{"at":3,"trapped":true},"dispatched":4,"delivered":5,"until":8}
  {"type":"traps.fault","cycle":8,"source":"load","pc":32,"cause":5,"value":12288,"handler":64,"csr":9,"retired_before":{"at":7,"trapped":false},"dispatched":10,"until":12}
  {"type":"traps.summary","cycles":13,"faults":2,"delivered":1,"unmatched":1}


  $ sed 's/"mtvec": "mtvec"/"mtvec": "mtvec_q"/' trap-core.json > renamed.json
  $ coralview traps --platform renamed.json traps.vcd
  platform trap-core does not match the trace (model traps):
    missing mtvec_q: mtvec
  [3]
