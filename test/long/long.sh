#!/usr/bin/env bash
# long.sh CORALVIEW MKELF RSS.PY: generate a long trace on the RVV core simulator, read it with the streamed
# views and print each one's peak RSS. LONG_CYCLES (default 3000000) sets the length; the views whose memory must
# not grow with the trace fail above LONG_RSS_KB (default 256000, about four times what they take).
# The trace is generated here and removed at the end.
set -euo pipefail
cv=$(realpath "$1") mkelf=$(realpath "$2") rss=$(realpath "$3")
coral=${CORALNPU:-/opt/coralnpu}
cycles=${LONG_CYCLES:-3000000}
ceiling=${LONG_RSS_KB:-256000}
sim=$coral/emulators/bin/rvv_core_mini_axi_sim
platform=rvv-core-mini-axi

if [ ! -x "$sim" ] || ! command -v python3 > /dev/null; then
  echo "long: needs $sim and python3; not run"
  exit 0
fi

d=$(mktemp -d "${TMPDIR:-/tmp}/coralview-long.XXXXXX")
trap 'rm -rf "$d"' EXIT
fail() { echo "long: $*" >&2; exit 1; }

# vsetivli, then loop { addi x1,x1,1; vadd.vv v1,v1,v1; jal x0,-8 }
"$mkelf" "$d/loop.elf" 0 prog=cc027057,00108093,021080d7,ff9ff06f
(cd "$d" && timeout --kill-after=5 3000 "$sim" --cycles="$cycles" --trace --binary="$d/loop.elf" > sim.log 2>&1) || true
fst=$(sed -n 's/.*for tracing: 1 ps (\(.*\.fst\)).*/\1/p' "$d/sim.log")
[ -n "$fst" ] && [ -s "$fst" ] || fail "the simulator wrote no trace"
mv "$fst" "$d/long.fst"
echo "trace: $cycles cycles, $(du -m "$d/long.fst" | cut -f1) MB"

: > "$d/summary"
# streamed NAME CMD...: a view whose memory is bounded; fails above the ceiling
streamed() {
  local n=$1; shift
  python3 -I "$rss" "$n" "$d/$n.out" "$d/$n.err" "$@" | tee -a "$d/summary"
}
# info NAME CMD...: measured and printed, not checked
info() {
  local n=$1; shift
  python3 -I "$rss" "$n" "$d/$n.out" "$d/$n.err" "$@" | tee -a "$d/info"
}

p="--platform $platform"
streamed commits_limit20 "$cv" commits $p --limit 20 "$d/long.fst"
streamed commits_profile "$cv" commits $p --limit 20 --profile 10 "$d/long.fst"
streamed stalls_profile "$cv" stalls $p --profile 10 "$d/long.fst"
streamed ops_text "$cv" ops $p --limit 20 "$d/long.fst"
streamed registers_text "$cv" registers $p "$d/long.fst"
streamed vectors_limit20 "$cv" vectors $p --limit 20 "$d/long.fst"
streamed commits_jsonl "$cv" commits $p --format jsonl --limit 100000000 "$d/long.fst"
streamed render_commits "$cv" render --limit 20 "$d/commits_jsonl.out"
streamed profile_commits "$cv" profile --rows 10 "$d/commits_jsonl.out"
streamed run_text "$cv" run $p --model commits --model stalls --model ops \
  --sink commits:text:"$d/run.commits.txt" --sink stalls:text:"$d/run.stalls.txt" --sink ops:text:"$d/run.ops.txt" "$d/long.fst"
streamed run_report "$cv" run $p --model commits --model stalls --model ops --report "$d/report.md" "$d/long.fst"
streamed run_kanata "$cv" run $p --kanata "$d/k.log" "$d/long.fst"
streamed run_jsonl "$cv" run $p --sink commits:jsonl:"$d/run.commits.jsonl" "$d/long.fst"
info run_perfetto "$cv" run $p --model stalls --model ops --perfetto "$d/trace.json" "$d/long.fst"

awk -v ceiling="$ceiling" '
  { split($2, a, "="); split($4, c, "=");
    if (c[2] != 0) { print "long: " $1 " failed, status " c[2]; bad = 1 }
    else if (a[2] > ceiling) { print "long: " $1 " used " a[2] " KB, over " ceiling; bad = 1 } }
  END { exit bad }' "$d/summary" >&2 || fail "a streamed view failed or used too much memory"
echo "long: all streamed views under $ceiling KB"
