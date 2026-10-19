# hwfrp: hardware models over waveform traces

`hwfrp` turns a VCD or FST waveform into per-cycle values, and runs models
written as dataflow graphs over them. A model says which signals it needs,
how to decode them, and what to compute from one cycle to the next. `hwfrp`
does the rest:

- finds the signals by path, and fails if any are missing;
- picks the settled phase of the clock;
- keeps the current value of every probed signal;
- re-evaluates only the parts of the graph whose inputs changed;
- reports X/Z values as diagnostics.

The waveform is read with [ovcd](https://github.com/TheCBaH/ovcd).

This document covers:

- [Quick start](#quick-start);
- [Concepts](#concepts): traces, clocks, signals, events, machines,
  binding, indexed state;
- [Machinery](#machinery): from FST bytes to a subscriber call;
- [Value compared with reading the trace directly](#value-compared-with-reading-the-trace-directly);
- [Limits and gotchas](#limits-and-gotchas);
- [Testing a model](#testing-a-model).

## Quick start

A trace has a clock `top.clk` and a ready/valid-style output
`top.io_out_valid` / `top.io_out_bits_data` (the names a Chisel
`Valid(UInt(8.W))` port gets). Print every transfer with its cycle, and how
long it has been since the previous one:

```ocaml
open Hwfrp
module Reference = Vcd_types.Reference

let transfers tr =
  let net = Net.create () in
  let at path = Reference.of_list path in
  let (Clock.Any clk) =
    Bind.clock net tr ~model:"demo" ~name:"clk" After_falling (at [ "top"; "clk" ])
  in
  let scope = Bind.root net tr clk ~model:"demo" (at [ "top" ]) in
  let out = Bundle.valid scope "io_out" in
  let data = Bundle.get out.v_bits "data" Bind.uint in
  let fired = Ev.tag (Sig.cycle clk) (Ev.when_ out.v_valid data) in
  let with_gap =
    Ev.scan ~init:None
      (fun last (d, c) -> (Some c, Some (d, c, Option.map (fun l -> c - l) last)))
      fired
  in
  Ev.subscribe with_gap (fun (d, c, gap) ->
      Printf.printf "cycle %d: %d%s\n" c d
        (match gap with Some g -> Printf.sprintf " (%d cycles after the last)" g | None -> ""));
  let sched = Result.get_ok (Sched.compile net) in
  ignore (Sched.run sched (Sampler.create tr (Net.domains net)))

let () = transfers (Trace.open_file "sim.fst")
```

```
cycle 0: 42
cycle 3: 7 (3 cycles after the last)
cycle 4: 8 (1 cycles after the last)
```

The example is compiled and its output checked by
`hwfrp/test/test_doc.ml`. The steps:

1. `Bind.clock` defines a clock domain. It samples the trace once per
   cycle, after the falling edge of `top.clk`.
2. `Bind.root` and `Bundle.valid` bind `io_out_valid` and the
   `io_out_bits_*` fields under `top`.
3. `Ev.when_` turns the valid signal and the data into an event that fires
   in the cycles where valid is high.
4. `Ev.tag` pairs each occurrence with the cycle number.
5. `Ev.scan` carries the last cycle from one occurrence to the next.
6. `Sched.compile` freezes the graph, and `Sched.run` pulls samples from the
   trace until it ends.

If `top.io_out_bits_data` were missing, or were 16 bits where `Bind.uint`
accepts up to 62, the first `Bind` call would raise
`Bind.Unbound (requirement, status)`. Nothing is substituted.

## Concepts

### Trace, slots, sampler

`Trace.open_file` opens a VCD or FST (detected by content) and reads its
header. A signal becomes *tracked* when a model binds it; each tracked
signal gets a dense integer *slot*. The tracked set is frozen when reading
starts (`Sampler.create` or `Trace.events`), and only the tracked signals'
changes are decoded: ovcd skips the others' (`~select:false` reads them
all).

`Sampler` turns the trace's value changes into *samples* of clock
domains. A clock domain is a 1-bit clock signal, an optional enable, and a
sample rule:

| Rule | Values seen at a sample | Use when |
|---|---|---|
| `After_falling` | after the changes of the timestamp where the clock fell | the trace dumps on both edges, as Verilator testbenches that call `dump` on each edge do; the low phase is settled |
| `Before_rising` | before the changes of the timestamp where the clock rose | the trace dumps once per cycle, after the rising edge |
| `After_rising` | after the changes of the rising-edge timestamp | the registered values right after the edge |

The changes of one timestamp are applied together. Domains sampling at the
same timestamp tick in a fixed order: `Before_rising` domains first, then
the changes are applied, then the `After_*` domains. Each sample carries
the domain's cycle index, the timestamp, whether the enable was high, and
the set of slots whose value changed since that domain's previous sample.

The property test in `hwfrp/test/test_props.ml` checks the sampled values
against ovcd's own `Vcd.Stateful` stream on 500 random traces, under all
three rules.

### Signals and events

A model is a graph of *nodes* built in a `Net.t`, in two kinds:

- **Signals** (`('a, 'c) Sig.t`) have a value at every sample: a decoded
  input, a register's state, a count.
- **Events** (`('a, 'c) Ev.t`) have a value only at the samples where they
  fire: a handshake, a retirement, a change.

The phantom type `'c` is the clock domain. A node's inputs must share its
domain; crossing domains takes `Clock_cross.resample`.

| Combinator | Meaning |
|---|---|
| `Sig.map`, `map2`, `let+ … and+ …`, `all` | combinational logic; recomputed only when an input changed |
| `Sig.pre ~init s` | `s` one sample earlier: a register |
| `Sig.hold ~init e` | the last value `e` fired |
| `Sig.fold ~init f e` | an accumulator over `e` |
| `Sig.changes s` | fires with the new value when `s` changes (never at the first sample) |
| `Sig.cycle`, `Sig.time`, `Sig.enabled` | the domain's own counters |
| `Ev.when_ c s` | fires with `s` at every sample where `c` holds |
| `Ev.gather [s0; s1; …]` | fires with the `Some` values of option signals: the valid lanes of a cycle |
| `Ev.rising`, `Ev.falling` | edges of a Boolean signal |
| `Ev.map`, `filter`, `filter_map`, `merge`, `union`, `tag`, `scan`, `flatten` | event algebra |
| `Machine.run spec s` | a state machine stepped on `s` (or at every sample), emitting a list per step and a final list at the end of the trace |
| `Clock_cross.resample s clk` | `s`'s last value, read at every sample of another domain |
| `Ev.subscribe e f` | runs `f` after each sample where `e` fired; the way out of the graph |
| `Source.many clk signals ~init update` | one node over many signals, updated with the indices that changed |
| `Diag.emit`, `Diag.report` | diagnostics with cycle, time and the paths to look at |

### Purity

The model is functional: node functions (`Sig.map`, `fold`, `Ev.scan`, …)
and `Machine` steps must be pure functions of their inputs. State that
lasts from one sample to the next lives in a machine's state or a `State`
store, as immutable values (`Map`, lists, records). Mutation belongs to
the engine (node values, the dirty heap, `Track`'s table, `Port` queues)
and to sinks: `Ev.subscribe` is the way out of the graph. Local mutation
inside a function that is pure from outside is fine.

State captured in closures and mutated by a step works only while the
step runs once per sample. It cannot be snapshotted for replay, is shared
if the same value is built into two nets, and an in-place update looks
like "no change" to the scheduler, whose default `eq` is physical
equality.

### Binding

`Bind` connects nodes to trace signals by path and records each one as a
`requirement`: model, root, absolute path, width rule and purpose.

- A *decoder* turns the sampled 4-state value into an OCaml value:
  - `bool`: exactly 1 bit;
  - `uint`: up to 62 bits;
  - `bits`: any width, as `Bits.t`;
  - `logic`: X/Z kept;
  - `field ~lo ~width`: a slice.

  A sample with X or Z bits where the decoder needs 0/1 yields the
  decoder's `unknown` value and a `bind.unknown-bits` diagnostic.
- A probe that does not resolve raises `Bind.Unbound`: the signal is
  missing, has a width the decoder rejects, or is real or string where bits
  are expected. There are no stand-in values and no optional probes. A
  model that knows a signal may be absent must know it from a description
  of the hardware; Coral's are in [coralnpu.md](../doc/coralnpu.md).
- `Bind.requirements net` lists what a model bound, and `Bind.check`
  resolves a requirement list against any trace. `coralview check` is built
  on these two.

`Bundle` knows Chisel's flattening of bundles into port names:

- `Bundle.valid scope "io_x"` gives `io_x_valid` and the `io_x_bits_*`
  fields;
- `Bundle.decoupled` adds `_ready`;
- `Bundle.lanes scope "io_x_%d_valid"` lists the lane numbers present.
  That one is a browsing aid: models take lane counts from a description.

### Indexed state

`State` keeps indexed hardware state (register files, scoreboards, tile
and vector register files) up to date incrementally. A *store* has two
parts:

- a signal holding an immutable snapshot (`'v State.t`, keyed by integer),
  so the state at any past sample stays valid;
- an event with the entries that changed in a sample.

| Constructor | Builds the store from |
|---|---|
| `State.mirror scope [(key, name); …] decoder` | storage the trace holds, one signal per entry |
| `State.mirror_fields scope [(key, [(name, width); …]); …] combine` | entries split over several signals, such as a float register kept as sign, exponent and mantissa |
| `State.mirror_packed scope name ~entries ~width decode` | a packed array `logic [entries-1:0][width-1:0]` |
| `State.replay ~init merge writes` | events of `(key, write)` lists: write ports, retirements |
| `State.previous clk store` | the same store one sample later, for storage a write updates at the next clock edge |

Mirrors are built on `Source.many`, one engine node for many signals. The
node runs only when one of its signals changes and receives just the
changed ones, so a 32-entry register file costs work only for the
registers written that cycle.

`State.relate clk net ~source ~code ~keys dirty check` states a relation
between stores. It checks every key at the first sample. After that it
rechecks only the keys named by the `dirty` events (usually
`State.keys store` of each store the check reads), and emits a diagnostic
when a key starts failing.

`hwfrp/test/test_state.ml` checks each constructor, `previous` and
`relate` against a naive rebuild of the whole state at every sample, on
300 random traces each. The first run found shared signals in
`mirror_fields` being dropped; that is fixed.

### Pulling events: Run and Port

`Sched.run` evaluates a whole trace and reports through subscribers. A
consumer that wants the events as a value instead reads them through a
`Port`, created on an event before the net is compiled:

```ocaml
let transfers_seq tr =
  let net = Net.create () in
  let at path = Reference.of_list path in
  let (Clock.Any clk) =
    Bind.clock net tr ~model:"demo" ~name:"clk" After_falling (at [ "top"; "clk" ])
  in
  let scope = Bind.root net tr clk ~model:"demo" (at [ "top" ]) in
  let out = Bundle.valid scope "io_out" in
  let data = Bundle.get out.v_bits "data" Bind.uint in
  let port = Port.create (Ev.tag (Sig.cycle clk) (Ev.when_ out.v_valid data)) in
  let sched = Result.get_ok (Sched.compile net) in
  Port.seq (Run.start sched (Sampler.create tr (Net.domains net))) port
```

`Run.start`, `Run.step` and `Run.finish` are `Sched.run` taken apart:
`step` evaluates one sample, and `finish` evaluates the rest and then the
finishers. The sequence steps the run only as far as it is read, so
`Seq.take 1` on the quick-start trace stops after its first sample:

```
42 at cycle 0
```

Rules:

- The sequence is **ephemeral**: it advances a live run. Traversing it
  twice, or asking a port for a second sequence, raises
  `Invalid_argument`.
- It gives the same occurrences, in the same order, as a subscriber of
  the event; the occurrences finishers fire come last.
- Several ports of one run share its samples. Reading one fills the
  queues of the others (`Port.pending`), so reading one stream to its end
  buffers all the others. Several consumers of one pass should subscribe
  instead.

### Outcomes known later: Track

Many outcomes are known later than they start: a request and its
response, a job and its completion, an instruction and its retirement.
`Track.run` keeps such entries by key. It takes an event of operations
(`Open (k, v)`, `Update (k, f)`, `Close k`) and fires each entry once:
`Closed v` when it is closed, `Open_at_end v` for what is still open when
the trace ends, or `Displaced v` when its key is opened again while it is
open. Keys may be reused once closed. Re-opening an open key, or updating
or closing a key that is not open, records a diagnostic.

The valid bursts of the quick-start trace as `Span`s:

```ocaml
let bursts tr =
  let net = Net.create () in
  let at path = Reference.of_list path in
  let (Clock.Any clk) =
    Bind.clock net tr ~model:"demo" ~name:"clk" After_falling (at [ "top"; "clk" ])
  in
  let scope = Bind.root net tr clk ~model:"demo" (at [ "top" ]) in
  let valid = (Bundle.valid scope "io_out").v_valid in
  let edges = Sig.map2 (fun now before -> (now, before)) valid (Sig.pre ~init:false valid) in
  let ops =
    Ev.filter_map
      (fun ((now, before), c) ->
        match (now, before) with
        | true, false -> Some [ Track.Open ((), { Span.start = c; stop = None }) ]
        | false, true ->
            Some [ Track.Update ((), fun s -> { s with stop = Some (c - 1) }); Close () ]
        | _ -> None)
      (Ev.tag (Sig.cycle clk) (Ev.when_ (Sig.const clk true) edges))
  in
  Ev.subscribe (Track.run ops)
    (List.iter (function Track.Closed s | Open_at_end s | Displaced s ->
        Printf.printf "burst from cycle %d, %s\n" s.Span.start
          (match Span.length s with Some n -> Printf.sprintf "%d cycles" n | None -> "open")));
  ignore (Sched.run (Result.get_ok (Sched.compile net)) (Sampler.create tr (Net.domains net)))
```

```
burst from cycle 0, 1 cycles
burst from cycle 3, 2 cycles
```

### Spans, transactions and reducers

`Span.t` is an interval of cycles, both ends included, open (`stop =
None`) when the trace ended first. `Transaction.t` is a bus request and
its response: ID, direction, address, bytes, beats, the cycles of the
request, its acceptance, the first data and completion, the response
status, and the transactions outstanding at acceptance.
`Transaction.latency` counts from acceptance to completion,
`Transaction.throughput` is bytes per cycle from the request on. These
are plain records, with no serialization; tools give them codecs.

`Reduce` folds sequences into summaries: `Stats` (count, min, max, sum,
mean), `Histogram` (counts per integer) and `Group.by` (a fold per key,
keys in order of first appearance). Over the pulled transfers above:

```ocaml
let stats tr = Reduce.Stats.of_seq (Seq.map fst (transfers_seq tr))
```

```
n 3, min 7, max 42, mean 19.00
```

`make hwfrp-boundary` builds and tests the `hwfrp` package alone and
fails if its libraries use anything beyond ovcd and unix. Bus protocols
(AXI4, TileLink-UL) are hardware vocabulary and live with the tool that
models the hardware: coralview's `src/proto`.

## Machinery

What happens between the FST file and a subscriber call:

```
FST blocks ──ocaml-fst──> value changes ──Vcd_fst──> Timestamp / Change (ID, Value) events
   │                                                        │
   └─ header ──> Vcd.Resolver (paths -> IDs) ──> Trace (slots for bound signals)
                                                            │
                         Sampler: batch per timestamp, clock edges, sample rules
                                                            │ tick (domain, cycle, time, changed slots)
                         Sched: dirty nodes from changed slots, delays, every-tick nodes
                                                            │ settle in node order
                         subscribers, diagnostics, finish outputs
```

1. **Reading.** ocaml-fst decodes one value-change block at a time.
   `Vcd_fst` turns it into the same event stream ovcd's VCD parser
   produces, so memory stays flat however long the trace is.
2. **Sampling.** `Sampler` keeps the current value of every tracked slot in
   an array, and drops changes to untracked signals by ID. At each timestamp
   it detects edges of each domain's clock from the last change in the
   batch, queues the domain's sample before or after applying the batch,
   and records which slots changed per domain. A 4-state `Logic.t` view of
   a slot is cached until the slot changes again.
3. **Scheduling.** Node ids are creation order, which is a topological
   order: a node exists before anything reads it. For each sample of
   domain d, `Sched.step` does the following:
   1. clears the events d fired in its previous sample;
   2. latches the `pre` registers (newest first, so `pre (pre s)` shifts
      correctly);
   3. updates `cycle`/`time`/`enabled`;
   4. marks the sources of the changed slots, and the every-sample nodes
      (`when_`, `gather`, `resample`, machines with `every_tick`);
   5. evaluates marked nodes in id order from a heap; a node whose value
      changed (or event that fired) marks its successors;
   6. runs d's subscribers in registration order.

   At the end of the trace, each machine's `finish` output propagates
   through the graph once more (machines do not step then).
4. **Equivalence.** `Sched.Sweep` is a second strategy that scans every
   node of the domain for a changed input instead of using the heap. The
   property test compares three things on 1,000 random programs over random
   traces:
   - the incremental scheduler;
   - `Sweep`;
   - an interpreter that implements each combinator's semantics directly
     and knows each operator's inputs itself.

   They print identical per-sample logs. When six engine mutations were
   tried, the test caught every mutation that changes behaviour.
   Two more properties on 1,000 random programs each: `Sched.run` and a
   loop of `Run.step` give the same logs and tick counts, and up to three
   ports read in a random interleaving each give exactly what a
   subscriber of the same event sees, finisher events included.

Cost is proportional to the number of value changes of the bound signals,
plus the nodes they reach. On the Coral VME `matrix.elf` trace (159,567
variables, 1,084 cycles), `coralview bench` measures this split:

| Step | Time |
|---|---|
| FST header | 0.12–0.14 s |
| ovcd `Vcd.Resolver.make` (paths -> IDs, all 79,512 signals) | 0.84–0.98 s |
| Decoding every value change and sampling 408 signals | 0.17–0.24 s |
| Evaluating a 900-node graph (66k–148k node evaluations) | under 0.05 s |

Opening the hierarchy dominates. Selected-signal decoding (HO-092) is in;
path lookup without the full resolver (HO-093) is still planned.

## Value compared with reading the trace directly

The same quick-start task, written against ovcd alone, is also in
`hwfrp/test/test_doc.ml` and prints the same three lines:

```ocaml
let transfers_raw text =
  let { Vcd.header; simulation } = Vcd.parse_string text in
  let resolver = Vcd.Resolver.make header in
  let id path = Option.get (Vcd.Resolver.find_id resolver (Reference.of_string path)) in
  let clk = id "top.clk" and valid = id "top.io_out_valid" and data = id "top.io_out_bits_data" in
  let values = Hashtbl.create 8 in
  let get i = Hashtbl.find_opt values (Vcd_types.ID.to_string i) in
  let cycle = ref 0 and last = ref None and batch = ref [] in
  let sample () =
    (match (get valid, get data) with
    | Some (Vcd_types.Value.Scalar B1), Some (Int d) ->
        Printf.printf "cycle %d: %d%s\n" !cycle d
          (match !last with
          | Some l -> Printf.sprintf " (%d cycles after the last)" (!cycle - l)
          | None -> "");
        last := Some !cycle
    | _ -> ());
    incr cycle
  in
  (* The changes of one timestamp are applied together; a falling clock edge then samples. *)
  let flush () =
    let before = get clk in
    List.iter (fun (i, v) -> Hashtbl.replace values (Vcd_types.ID.to_string i) v) (List.rev !batch);
    batch := [];
    match (before, get clk) with Some (Scalar B1), Some (Scalar B0) -> sample () | _ -> ()
  in
  Seq.iter
    (function
      | Vcd_ast.Timestamp _ -> flush ()
      | Change (i, v) -> batch := (i, v) :: !batch
      | DumpStart _ | DumpEnd | SimComment _ -> ())
    simulation;
  flush ()
```

For one handshake this is about as long as the `hwfrp` version, and simpler
to follow. The difference is in what each version leaves to the author, and
it grows with every signal and every model:

| Concern | Raw | hwfrp |
|---|---|---|
| Which phase is settled, edge detection, grouping changes per timestamp | hand-written per tool; easy to stamp a sample with the wrong timestamp (an early `Sampler` did, caught by its expect test) | a sample rule per clock, tested against `Vcd.Stateful` |
| Missing signal, wrong width, real instead of bits | `Option.get` raises, or a silently wrong decode (`Int d` does not match an `Int64` for 25–64 bits) | `Bind.Unbound` names the path, the width expected and found, and the purpose |
| Decoding `Value.t` (`Scalar`, `Int`, `Int64`, `Bytes`, `Scalars` with X) | a match per use | decoders, with X/Z as diagnostics |
| Registers and joins across cycles | refs updated in the right order | `Sig.pre`, `hold`, `fold`, `scan`, `Machine` |
| Several lanes per cycle | loops over names | `Ev.gather`, `Bundle` |
| Two clock domains at shared timestamps | ordering rules written again | `Clock.define` twice; `Clock_cross` |
| Work per cycle | everything, every cycle | only nodes whose inputs changed |
| Several models on one trace, each listing what it needs | ad hoc | `Bind.requirements` / `check` |
| End of trace (flush the last transaction) | remember to | `Machine.finish` |

The Coral models show the effect on real ports:

- The `memory` model pairs each LSU read with the data that arrives one
  cycle later in one expression: `let+ prev = pre ~init:None req and+ rdata
  = rdata in …`.
- The `commits` model joins three port groups (4 dispatch lanes,
  6 + 2 writeback ports, 8 retirement lanes) through one `Machine`, about
  90 lines including the cycle accounting.
- The `stalls` model is a classification over 4 lanes × 7 wires plus
  8 shared inputs, about 50 lines of binding.

In each case the model code holds the hardware's logic, not trace
mechanics.

## Limits and gotchas

- **Clock types are existential.** `Clock.define` and `Bind.clock` return
  `Clock.Any c`. Code that builds a model must be polymorphic in `'c`
  (pattern-match where the model is built, or pass a record with a
  polymorphic field), not return `'c` values out of that scope.
- **Maps run once when built.** `Sig.map f s` computes `f` on `s`'s initial
  value to get its own initial value, so `f` must accept the decoder's
  `unknown` value (e.g. `Bits.zero width`).
- **A change is a new value by physical equality** unless `?eq` is given.
  A map that builds a new record or list each time counts as a change, so
  its successors are re-evaluated. That is correct but costs evaluations;
  give `~eq` for structural comparison where it matters.
- **Per-cycle lists need every-sample nodes.** A lane that stays valid for
  two cycles is two occurrences, so `when_` and `gather` evaluate at every
  sample. They are cheap but not incremental.
- **Track keys one entry per key.** Several entries outstanding under one
  key, as AXI allows per ID, need a queue per key in a `Machine`.
- **SystemVerilog packed structs** come through as one flat vector. Field
  layouts (HO-050/051) are planned; until then models slice vectors
  themselves, as `tiles` does for the VME ports.

## Testing a model

- **Expect tests on hand-written VCDs.** `Trace.of_string` reads a VCD
  literal. See `hwfrp/test/test_bind.ml` and `test_frp.ml`.
- **Cram tests of a whole command.** Use small VCD fixtures and a platform
  description, as in `test/platform.t`.
- **`check` against real traces.** It binds every model of a platform
  without simulating, and fails on the first probe that does not resolve.
- **Engine changes.** Run `test_props.ml`; add the new combinator to its
  generator and to the reference interpreter.
