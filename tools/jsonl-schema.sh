#!/usr/bin/env bash
# jsonl-schema.sh FILE.jsonl...: the members of each JSONL record type, as dotted paths ([] for array
# elements), from the records in the files.
set -euo pipefail
jq -rs '
  group_by(.type)[]
  | .[0].type + ":" + ([.[] | [paths(type != "object" and type != "array") | map(if type == "number" then "[]" else . end)
      | join(".") | gsub("\\.\\[\\]"; "[]")]] | add | unique | map(select(. != "type"))
      | map(" " + .) | join(""))' "$@"
