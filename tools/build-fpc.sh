#!/usr/bin/env sh
set -eu
if [ "$#" -lt 1 ]; then
  printf 'Usage: %s path/to/program.dpr [fpc-options...]\n' "$0" >&2
  exit 2
fi
command -v fpc >/dev/null 2>&1 || { printf 'FPC not available\n' >&2; exit 127; }
source_file=$1
shift
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ -f "$source_file" ] || { printf 'Missing source: %s\n' "$source_file" >&2; exit 2; }
mkdir -p build/fpc/units bin/fpc
fpc -Mdelphi -B -Cr -Co -Fu"$repo_root/src" -FUbuild/fpc/units -FEbin/fpc "$@" "$source_file"
