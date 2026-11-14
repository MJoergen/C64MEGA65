#!/usr/bin/env bash
# Builds inputmon.prg from inputmon.bas with petcat of VICE (BASIC V2, load address $0801).
# The source is written with uppercase keywords as on a C64 screen; petcat expects lowercase
# keywords in its ASCII input, so the source is lowercased on the way in (the letters inside
# the strings then become the uppercase PETSCII letters that the C64 shows).
# PETCAT can point to another petcat binary (default: the macOS VICE installation).
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd -P)"
PETCAT="${PETCAT:-/Applications/Vice/bin/petcat}"
TMP="$(mktemp "${TMPDIR:-/tmp}/inputmon.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
tr 'A-Z' 'a-z' < "$HERE/inputmon.bas" > "$TMP"
rm -f "$HERE/inputmon.prg"
"$PETCAT" -w2 -l 0801 -o "$HERE/inputmon.prg" -- "$TMP"
echo "inputmon.prg: $(wc -c < "$HERE/inputmon.prg" | tr -d ' ') bytes"
