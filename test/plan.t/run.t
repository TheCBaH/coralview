A catalog is a trace of the simulator build whose events are not read. This one
has a signal, extra_status, that no model needs:

  $ t=../platform.t
  $ p=$t/test-core.json
  $ awk 'NR == 14 { print; print "$var wire 8 , extra_status $end"; next } 1' $t/core.vcd > catalog.vcd

The plan for commits, and for extra_status read by `coralview signals`:

  $ coralview plan --platform $p --model commits --signal TOP.core/extra_status --catalog catalog.vcd -o out
  $ cat out/select
  $ cat out/plan
  $ coralview plan --platform $p --model commits --signal TOP.core/extra_status --catalog catalog.vcd -o out --format jsonl

The plan holds for the origins a run builds. The commits plan passes with commits alone, and the
signal with `signals`, on a trace that has only what each needs:

  $ coralview commits --platform $p $t/core.vcd > baseline.txt
  $ coralview commits --platform $p --plan out/plan $t/core.vcd | cmp - baseline.txt
  $ coralview run --platform $p --model commits --plan out/plan $t/core.vcd | cmp - baseline.txt
  $ coralview signals --platform $p --plan out/plan catalog.vcd TOP.core/extra_status | head -n 2

Only the sampled mode is planned:

  $ coralview signals --platform $p --raw --plan out/plan catalog.vcd TOP.core/extra_status
  [2]

A signal narrower than planned, which the width rule accepts:

  $ sed 's/wire 32 # io_debug_dispatch_0_instAddr/wire 16 # io_debug_dispatch_0_instAddr/' $t/core.vcd > narrow.vcd
  $ coralview commits --platform $p narrow.vcd | cmp - baseline.txt
  $ coralview commits --platform $p --plan out/plan narrow.vcd
  [3]

A changed alias group:

  $ sed 's/^\$var wire 1 ! io_aclk \$end$/&\n$var wire 1 ! io_aclk_copy $end/' $t/core.vcd > alias.vcd
  $ coralview commits --platform $p --plan out/plan alias.vcd
  [3]

A binding the run drops, here the trap bit of the retirement port:

  $ sed 's/"trap": true/"trap": false/' $p > notrap.json
  $ coralview commits --platform notrap.json --plan out/plan $t/core.vcd
  [3]

A signal missing at run time is the ordinary binding error:

  $ coralview commits --platform $p --plan out/plan $t/partial.vcd
  [3]
  $ coralview signals --platform $p --plan out/plan $t/core.vcd TOP.core/extra_status
  [3]

An origin the plan does not have, and a plan that is not one:

  $ coralview plan --platform $p --model commits --catalog $t/core.vcd -o commits-only
  $ coralview signals --platform $p --plan commits-only/plan $t/core.vcd TOP.core/io_aclk
  [3]
  $ echo nonsense > bad.plan
  $ coralview commits --platform $p --plan bad.plan $t/core.vcd
  [2]
  $ coralview commits --platform $p --plan missing.plan $t/core.vcd
  [2]

Catalogs of one simulator must agree; these two differ in the width of a signal:

  $ coralview plan --platform $p --model commits --catalog $t/core.vcd --catalog narrow.vcd -o both
  [3]
  $ coralview plan --platform $p --model commits --catalog $t/core.vcd --catalog $t/core.vcd -o twice
  $ cmp twice/plan commits-only/plan
