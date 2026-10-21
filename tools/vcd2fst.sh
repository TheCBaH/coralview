#!/bin/sh
# usage: vcd2fst.sh LIBFST_DIR in.vcd out.fst
# LIBFST_DIR is a libfst checkout (ocaml-fst's vendor/libfst); needs gcc and zlib.
set -eu
lib=$1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
gcc -O1 -I "$lib/src" -o "$tmp/vcd2fst" "$(dirname "$0")/vcd2fst.c" \
  "$lib/src/fstapi.c" "$lib/src/fastlz.c" "$lib/src/lz4.c" -lz -lpthread
"$tmp/vcd2fst" "$2" "$3"
