A description can extend another: its members are applied over the base's, as a
JSON merge patch. Objects merge member by member, anything else replaces the
base's value, and null removes it. The base is a file, relative to the extending
one, or a built-in description. A base is the one-lane test core of platform.t:

  $ t=../platform.t
  $ cp $t/core.vcd .
  $ sed '/"name": "test"/s/test/base/' $t/test-core.json > base.json

An overlay that gives another name and configuration, the sample rule, and one
wire of one block; everything else is the base's:

  $ cat > derived.json <<'END'
  > {
  >   "schema_version": "1.0",
  >   "name": "derived",
  >   "extends": "base.json",
  >   "configurations": [ { "name": "derived-core", "top_level": "Core", "trace_root": ["TOP", "core"] } ],
  >   "sample": "before_rising",
  >   "blocks": { "dispatch_debug": { "inst": "io_debug_dispatch_%d_instAddr" } }
  > }
  > END
  $ coralview check --platform derived.json core.vcd
  platform derived-core
  commits at TOP.core
    bound   io_aclk 1: core clock
    bound   io_debug_dispatch_0_instFire 1: dispatch lane fires
    bound   io_debug_dispatch_0_instAddr 32: dispatched PC
    bound   io_debug_dispatch_0_instAddr 32: dispatched word
    bound   io_debug_regfile_writeData_0_valid 1: regfile writeback
    bound   io_debug_regfile_writeData_0_bits_addr 5: written register
    bound   io_debug_regfile_writeData_0_bits_data 32: written value
    bound   io_debug_rb_inst_0_valid 1: retirement lane valid
    bound   io_debug_rb_inst_0_bits_pc 32: retired PC
    bound   io_debug_rb_inst_0_bits_idx 7: retired destination index
    bound   io_debug_rb_inst_0_bits_trap 1: retired with a trap
  $ coralview signals --platform derived.json core.vcd TOP/core/io_aclk --to-cycle 1
  # sampled before_rising on io_aclk at TOP.core
         0          1    1 TOP/core/io_aclk 0x0
         1          3    1 TOP/core/io_aclk 0x0

The base is found relative to the file that names it, and bases chain. A null
removes a member of the base, here a whole block, which the models that need it
then report:

  $ mkdir sub
  $ cat > sub/grand.json <<'END'
  > {
  >   "schema_version": "1.0",
  >   "name": "grand",
  >   "extends": "../derived.json",
  >   "configurations": [ { "name": "grand-core", "top_level": "Core", "trace_root": ["TOP", "core"] } ],
  >   "blocks": { "regfile_writeback": null }
  > }
  > END
  $ coralview commits --platform sub/grand.json core.vcd
  platform grand-core describes no regfile_writeback block
  [2]

A base that does not exist, a base that is not a string, and a cycle are
reported at the member that names them:

  $ sed 's/"base.json"/"nobase.json"/' derived.json > lost.json
  $ coralview check --platform lost.json core.vcd
  extends: cannot read nobase.json
  File "lost.json", line 4, characters 13-26:
  [2]
  $ sed 's/"base.json"/["base.json"]/' derived.json > list.json
  $ coralview check --platform list.json core.vcd
  extends: the name of a description to extend is a string
  File "list.json", line 4, characters 13-26:
  [2]
  $ sed 's/"base.json"/"nobody"/' derived.json > nobody.json
  $ coralview check --platform nobody.json core.vcd
  extends: no built-in description nobody (a file is a path ending in .json)
  File "nobody.json", line 4, characters 13-21:
  [2]
  $ sed 's/"base.json"/"b.json"/' derived.json > a.json
  $ sed 's/"base.json"/"c.json"/' derived.json > b.json
  $ sed 's/"base.json"/"a.json"/' derived.json > c.json
  $ coralview check --platform a.json core.vcd
  extends: a cycle, a.json -> b.json -> c.json -> a.json
  File "c.json", line 4, characters 13-21:
  [2]
  $ sed 's/"base.json"/"self.json"/' derived.json > self.json
  $ coralview check --platform self.json core.vcd
  extends: a cycle, self.json -> self.json
  File "self.json", line 4, characters 13-24:
  [2]

An error is reported where the member is: at the base's file for a block the overlay
does not touch, at the overlay for one it patches, and at the overlay for its own members:

  $ sed -e 's/"lanes": 1,/"lanes": 2,/g' -e 's/io_debug_dispatch_%d_inst/dp_/g' base.json > twolanes.json
  $ cat > inherit.json <<'END'
  > {
  >   "schema_version": "1.0",
  >   "name": "inherit",
  >   "extends": "twolanes.json",
  >   "configurations": [ { "name": "inherit-core", "top_level": "Core", "trace_root": ["TOP", "core"] } ]
  > }
  > END
  $ coralview check --platform inherit.json core.vcd
  dispatch_debug: "dp_Fire" has no %d for its 2 lanes
  File "twolanes.json", lines 10-11, characters 22-63:
  File "twolanes.json", line 10, characters 4-20: in member dispatch_debug of
  File "twolanes.json", lines 9-17, characters 12-3: blocks object
  File "twolanes.json", line 9, characters 2-10: in member blocks of
  File "inherit.json", lines 1-6, characters 0-1: platform object
  [2]
  $ sed 's/"base.json"/"twolanes.json"/' derived.json > over-twolanes.json
  $ coralview check --platform over-twolanes.json core.vcd
  dispatch_debug: "dp_Fire" has no %d for its 2 lanes
  File "over-twolanes.json", line 7, characters 32-75:
  File "over-twolanes.json", line 7, characters 14-30: in member dispatch_debug of
  File "over-twolanes.json", line 7, characters 12-77: blocks object
  File "over-twolanes.json", line 7, characters 2-10: in member blocks of
  File "over-twolanes.json", lines 1-8, characters 0-1: platform object
  [2]
  $ sed 's/"sample": "before_rising"/"sample": "never"/' derived.json > over-never.json
  $ coralview check --platform over-never.json core.vcd
  Unexpected sample rule enum string value: never. Must be after_falling,
  before_rising or after_rising.
  File "over-never.json", line 6, characters 12-19:
  File "over-never.json", line 6, characters 2-10: in member sample of
  File "over-never.json", lines 1-8, characters 0-1: platform object
  [2]
  $ sed '1s/{/{ "unknown": 1,/' derived.json > unknown.json
  $ coralview check --platform unknown.json core.vcd
  Unexpected member unknown for platform object
  File "unknown.json", lines 1-8, characters 0-1:
  [2]

A base that is not valid JSON is reported at its own file:

  $ sed '1s/{/[/' base.json > broken.json
  $ sed 's/"base.json"/"broken.json"/' derived.json > over-broken.json
  $ coralview check --platform over-broken.json core.vcd
  Expected , or ] after array element but found :
  File "broken.json", line 2, characters 18-19:
  [2]
