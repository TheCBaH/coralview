# Windows

`--from-cycle`, `--to-cycle` and `--pc` select a part of a run: one kernel
between two `csrr … mcycle` reads, one function, one loop. This note fixes
what a window covers. It is the contract of the cycle-estimate work (CS-010
of the plan); the commits that follow implement it model by model.

## Rules

1. **An event is in the window by its own cycle.** For `commits` that is the
   **retire** cycle (what the rows already use), for the other models the
   cycle of the event they print. An instruction dispatched before `--from-cycle`
   and retired inside it belongs to the window; one dispatched inside and
   retired after `--to-cycle` does not. The edge cases are the ones a reader
   of the printed rows sees, so rows and totals agree.
2. **With `--pc`, an event is in the window only if its PC is listed.** Events
   without a PC (stalls of an idle core, bus beats of no instruction) are
   outside a PC window.
3. **The run is not windowed, its output is.** Every model still reads the whole
   trace: dispatch and writeback state, the in-flight queue, the scoreboard
   carry across the edges, so the charge of a cycle inside the window is the
   one the whole-trace run gives it. A window never changes an event.
4. **Whole-trace output is untouched.** Without a window, text and JSONL are
   byte-identical to before. With one, the rows and the new window figures
   below are added; the existing whole-trace summary line stays and says it
   is the whole trace.
5. **A window is a sum of its rows.** `commits --profile` shares and the
   window summary add up over the windowed commits only: `share` is of the
   cycles charged inside the window, not of the run.

## Output

- Text: after the whole-trace summary line, one line
  `window [first, last]: N events, C cycles` (the cycles the model charges,
  where it charges: `commits`' `charged`, `stalls`' stalled cycles, and so on).
  `--profile` and the stall breakdown are computed from the windowed events and
  say so in their heading.
- JSONL: the summary record keeps its whole-trace fields and gains
  `window: {first, last, pcs}`, with the windowed totals beside it, only when a
  window is given. `schema_version` changes only if an existing field changes
  shape; none does.

## Per model

| Model | Event in the window | Windowed totals |
| --- | --- | --- |
| `commits` | retire cycle, PC | commits, charged cycles, profile shares |
| `stalls` | the cycle of the stall | cycles per cause |
| `memory`, `axi` | the accepted cycle of the request | requests, bytes, latency stats |
| `tiles`, `ops` | the cycle of the operation | operations, ops, per-class counts |

`registers`, `traps`, `vectors` and `dma` already print only rows; their
windows stay as they are until one of them needs totals.

## Windows from markers and symbols

Both only produce the `first`/`last` pair; the rules above apply unchanged.

- `--between-pc A,B [--nth N]`: from the Nth retirement of PC A to the next
  retirement of PC B, both included. Found by a first pass with `commits`, so
  the trace is a file. Intersects with `--from-cycle`/`--to-cycle`.
- `--around-symbol NAME --elf FILE [--nth N]` (not implemented; needs the ELF
  reader): from the Nth retirement of the symbol's address to the first
  retirement of a `ret` (`jalr x0, 0(ra)`) whose PC is inside the symbol's
  `[address, address + size)`. This is the simple rule, chosen on purpose:
  a function that returns early through a different `ret` ends its window
  there, and a function that leaves by a tail call has no `ret` and is an
  error (`--between-pc` still works for it). Call depth is not tracked, so a
  recursive function ends at its innermost return.
  Tracking depth over `jal`/`jalr` links is the refinement if the simple rule
  proves too coarse.
