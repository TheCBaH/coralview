#!/bin/sh
# check-install.sh PLATFORM.json TRACE: builds tools/consumer outside this workspace against the installed
# coralview (an opam switch with only its declared dependencies, e.g. `opam install coralview` from an archive of
# this tree without vendor/rivet) and runs it and the installed executable on a trace.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$here"/consumer/dune-project "$here"/consumer/dune "$here"/consumer/consumer.ml "$tmp"
dune build --root "$tmp" ./consumer.exe
"$tmp/_build/default/consumer.exe" "$1" "$2"
coralview memory --platform "$1" "$2" | tail -1
