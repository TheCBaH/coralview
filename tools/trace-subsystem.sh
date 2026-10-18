#!/usr/bin/env bash
# trace-subsystem.sh ARCHIVE VARIANT ELF ITCM_KB DTCM_KB DIR
# Runs a subsystem program as the archive's smoke.sh does (backdoor ELF load, then the loader over
# the SPI DPI port), with tracing; waits for its CORAL_ marker and leaves DIR/sim.fst.
set -euo pipefail
archive=$1 variant=$2 elf=$(realpath "$3") itcm=$4 dtcm=$5 dir=$6
mkdir -p "$dir"
cd "$dir"
rm -f ./*.log sim.fst
ln -sf "$archive/share/grey_bars_320x240.raw" .
port=$((5600 + RANDOM % 400))
SPI_DPI_PORT=$port "$archive/bin/Vchip_$variant" --load_elf="$elf" --trace > sim.out 2>&1 &
sim=$!
trap 'kill $sim 2>/dev/null || true' EXIT
timeout 120 bash -c "until grep -q 'DPI: Server listening on port $port' sim.out; do sleep 0.2; done"
SPI_DPI_PORT=$port timeout 300 python3 "$archive/tools/loader.py" --csr_only \
  --itcm_size_kbytes "$itcm" --dtcm_size_kbytes "$dtcm" "$elf" > loader.out
timeout 900 bash -c 'until grep -qs "CORAL_[A-Z_]*\(PASS\|FAIL\)" ./*.log; do sleep 0.5; done'
kill -INT $sim
wait $sim || true
trap - EXIT
cat ./*.log | tr -d '\r'
ls -l sim.fst
