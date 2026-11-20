#!/bin/sh
# Reads commits JSONL and checks that the charges of the retired and in-flight instructions, the
# discarded charges, and the cycles before the first dispatch and with nothing in flight add up to the
# cycles.
exec awk '
function num(k,   s) {
  if (!match($0, "\"" k "\":[0-9]+")) return 0
  s = substr($0, RSTART, RLENGTH); sub(/.*:/, "", s); return s + 0
}
/"type":"commits.commit"/ { retired += num("charged") }
/"type":"commits.in_flight"/ { flight += num("charged") }
/"type":"commits.summary"/ { cycles = num("cycles"); before = num("before"); empty = num("empty"); discarded = num("discarded") }
END {
  sum = retired + flight + discarded + before + empty
  printf "%d cycles = %d retired + %d in flight + %d discarded + %d before + %d empty%s\n",
    cycles, retired, flight, discarded, before, empty, (sum == cycles ? "" : "  MISMATCH: " sum)
  exit sum != cycles
}'
