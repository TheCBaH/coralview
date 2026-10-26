#!/usr/bin/env bash
# integration.sh selection|stream|selected-stream CORALVIEW CORALNPU
#
# The consumer against the archive's simulators: a selected FST read with the plan equals the full
# trace (selection); a VCD stream read from a pipe equals the saved VCD and the FST (stream); and
# both together (selected-stream). Skips when the archive has no catalogs.
set -euo pipefail
mode=$1 cv=$(realpath "$2") coral=$3
sims=$coral/emulators
platform=core-mini-axi
models="commits stalls memory axi registers traps"
elf=$sims/examples/memory.elf
cycles=5000000
signal=VCoreMiniAxi.core/CoreMiniAxi/io_halted

if [ ! -e "$sims/catalogs/core_mini_axi_sim.catalog.fst" ]; then
  echo "release $(cat "$coral/RELEASE" 2>/dev/null || echo '?') has no trace catalogs; $mode not run"
  exit 0
fi
if [ "$mode" != selection ] && [ ! -e "$sims/bin/core_mini_axi_vcd_sim" ]; then
  echo "release $(cat "$coral/RELEASE" 2>/dev/null || echo '?') has no VCD simulator; $mode not run"
  exit 0
fi

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
fail() { echo "integration: $*" >&2; exit 1; }

# plan DIR CATALOG: the plan for every model and the signal.
plan() {
  local args=()
  for m in $models; do args+=(--model "$m"); done
  "$cv" plan --platform $platform "${args[@]}" --signal $signal --catalog "$2" -o "$1"
}

# fst FILE [FLAGS]: the FST simulator, writing FILE.
fst() {
  local file=$1; shift
  timeout --kill-after=5 300 "$sims/bin/core_mini_axi_sim" --cycles=$cycles --trace_file="$file" \
    --binary="$elf" "$@" > "$d/sim.log" 2>&1
  grep -q CORAL_MEMORY_PASS "$d/sim.log" || { cat "$d/sim.log"; fail "memory.elf did not pass"; }
}

# analyses TRACE OUT [FLAGS]: every model's text and JSONL, a combined run, and the signal; one
# file each in OUT, so that two traces can be compared with diff -r. The trace's own name is
# dropped from the JSONL headers. Exit statuses are recorded.
analyses() {
  local trace=$1 out=$2; shift 2
  mkdir -p "$out"
  local st
  for m in $models; do
    set +e
    "$cv" "$m" --platform $platform "$@" "$trace" > "$out/$m.txt"
    echo $? > "$out/$m.status"
    "$cv" "$m" --platform $platform --format jsonl "$@" "$trace" | sed 's/"trace":"[^"]*"/"trace":""/' > "$out/$m.jsonl"
    set -e
  done
  local run=()
  for m in $models; do run+=(--model "$m"); done
  set +e
  "$cv" run --platform $platform "${run[@]}" "$@" "$trace" > "$out/run.txt"
  echo $? > "$out/run.status"
  "$cv" signals --platform $platform --changes --to-cycle 600 "$@" "$trace" $signal > "$out/signals.txt"
  echo $? > "$out/signals.status"
  set -e
}

compare() { diff -r "$1" "$2" > "$d/diff.txt" || { head -40 "$d/diff.txt"; fail "$3"; }; }

case "$mode" in
selection)
  fst "$d/full.fst"
  # Any complete trace of the build is a catalog; the shipped one must give the same plan.
  plan "$d/fst-plan" "$d/full.fst" | tee "$d/plan.out"
  fst "$d/selected.fst" --trace_select="$d/fst-plan/select"
  full=$(stat -c %s "$d/full.fst") selected=$(stat -c %s "$d/selected.fst")
  echo "FST: $full bytes full, $selected bytes selected"
  [ "$selected" -lt "$full" ] || fail "the selected trace is not smaller"
  planned=$(grep -c '^signal ' "$d/fst-plan/plan")
  declared=$("$cv" probe "$d/selected.fst" | sed -n 's/^signals //p')
  [ "$declared" = "$planned" ] || fail "the selected trace declares $declared signals, the plan has $planned"
  analyses "$d/full.fst" "$d/full"
  analyses "$d/selected.fst" "$d/selected" --plan "$d/fst-plan/plan"
  compare "$d/full" "$d/selected" "analyses of the selected trace differ from the full trace"
  plan "$d/catalog-plan" "$sims/catalogs/core_mini_axi_sim.catalog.fst" > /dev/null
  cmp "$d/fst-plan/plan" "$d/catalog-plan/plan" || fail "the shipped FST catalog gives a different plan than a full trace"
  # A plan made from a catalog of the VCD build names the same signals.
  if [ -e "$sims/catalogs/core_mini_axi_vcd_sim.catalog.vcd" ]; then
    plan "$d/vcd-plan" "$sims/catalogs/core_mini_axi_vcd_sim.catalog.vcd" > /dev/null
    diff "$d/fst-plan/plan" "$d/vcd-plan/plan" | head -20 || true
    cmp "$d/fst-plan/plan" "$d/vcd-plan/plan" || fail "the FST and VCD catalogs give different plans"
    diff <(sed 1,2d "$d/fst-plan/select") <(sed 1,2d "$d/vcd-plan/select") || fail "the manifests differ"
  fi
  echo "selection: ok"
  ;;
stream)
  vcd=$sims/bin/core_mini_axi_vcd_sim
  fst "$d/full.fst"
  timeout --kill-after=5 300 "$vcd" --cycles=$cycles --trace_file="$d/full.vcd" --binary="$elf" > "$d/sim.log" 2>&1
  grep -q CORAL_MEMORY_PASS "$d/sim.log" || fail "the VCD simulator did not pass"
  analyses "$d/full.fst" "$d/fst"
  analyses "$d/full.vcd" "$d/vcd"
  compare "$d/fst" "$d/vcd" "analyses of the VCD differ from the FST"
  # The stream: each analysis reads the VCD from a pipe as the simulator writes it.
  mkdir -p "$d/piped"
  for m in $models; do
    set +e
    bash -c 'set -o pipefail; "$1" --cycles="$2" --binary="$3" --trace_fd=3 3>&1 1>"$4" 2>&1 | "$5" "$6" --platform "$7" -' \
      _ "$vcd" $cycles "$elf" "$d/stream.log" "$cv" "$m" $platform > "$d/piped/$m.txt"
    pipeline=$?
    set -e
    echo "$m: pipeline status $pipeline"
    cmp "$d/piped/$m.txt" "$d/vcd/$m.txt" || fail "$m from a pipe differs from the saved VCD"
    [ "$pipeline" = "$(cat "$d/vcd/$m.status")" ] || fail "$m: pipeline status $pipeline, file status $(cat "$d/vcd/$m.status")"
  done
  # The consumer stops early: the simulator is gone when the pipeline is.
  set +e
  bash -c 'set -o pipefail; "$1" --cycles="$2" --binary="$3" --trace_fd=3 3>&1 1>"$4" 2>&1 | "$5" signals --platform "$6" --to-cycle 100 - "$7" > /dev/null' \
    _ "$vcd" $cycles "$elf" "$d/stream.log" "$cv" $platform $signal
  early=$?
  set -e
  echo "early stop: pipeline status $early"
  if pgrep -f "core_mini_axi_vcd_sim.*--trace_fd" > /dev/null; then fail "the simulator outlived its consumer"; fi
  # The producer fails after a valid prefix: the pipeline says so, the consumer summarises what it saw.
  timeout --kill-after=5 300 "$vcd" --cycles=2000 --trace_file="$d/prefix.vcd" --binary="$elf" > /dev/null 2>&1 || true
  set +e
  bash -c 'set -o pipefail; "$1" --cycles=2000 --binary="$2" --trace_fd=3 3>&1 1>"$3" 2>&1 | "$4" commits --platform "$5" -' \
    _ "$vcd" "$elf" "$d/stream.log" "$cv" $platform > "$d/prefix-piped.txt"
  failed=$?
  set -e
  echo "producer cut at the cycle limit: pipeline status $failed"
  [ "$failed" = 124 ] || fail "expected the cycle limit's status 124"
  "$cv" commits --platform $platform "$d/prefix.vcd" | cmp - "$d/prefix-piped.txt" || fail "the prefix summary differs"
  # The same through --exec, which also records how the simulator ended.
  "$cv" commits --platform $platform --exec "'$vcd' --cycles=$cycles --binary='$elf' --trace_fd=3 > '$d/exec.log' 2>&1" - > "$d/exec.txt"
  tail -n 1 "$d/exec.txt" | grep -q '^# producer: complete, exited with status 0$' || fail "--exec: no complete status"
  sed '$d' "$d/exec.txt" | cmp - "$d/vcd/commits.txt" || fail "--exec: the results differ"
  set +e
  "$cv" commits --platform $platform --exec "'$vcd' --cycles=2000 --binary='$elf' --trace_fd=3 > '$d/exec.log' 2>&1" - > "$d/exec-cut.txt"
  cut=$?
  set -e
  [ "$cut" = 4 ] || fail "--exec: a simulator stopped at the cycle limit gave status $cut, not 4"
  tail -n 1 "$d/exec-cut.txt" | grep -q 'failed, exited with status 124' || fail "--exec: no failed status"
  echo "stream: ok"
  ;;
selected-stream)
  vcd=$sims/bin/core_mini_axi_vcd_sim
  plan "$d/plan" "$sims/catalogs/core_mini_axi_vcd_sim.catalog.vcd" > /dev/null
  fst "$d/full.fst"
  analyses "$d/full.fst" "$d/full"
  for m in $models; do
    set +e
    bash -c 'set -o pipefail; "$1" --cycles="$2" --binary="$3" --trace_select="$4" --trace_fd=3 3>&1 1>"$5" 2>&1 | "$6" "$7" --platform "$8" --plan "$9" -' \
      _ "$vcd" $cycles "$elf" "$d/plan/select" "$d/stream.log" "$cv" "$m" $platform "$d/plan/plan" > "$d/selected-$m.txt"
    pipeline=$?
    set -e
    cmp "$d/selected-$m.txt" "$d/full/$m.txt" || fail "$m from a selected stream differs from the full FST"
    [ "$pipeline" = "$(cat "$d/full/$m.status")" ] || fail "$m: pipeline status $pipeline"
  done
  echo "selected-stream: ok"
  ;;
*) fail "unknown mode $mode" ;;
esac
