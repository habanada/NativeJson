#!/usr/bin/env sh
set -u
FPC=${FPC:-fpc}
command -v "$FPC" >/dev/null 2>&1 || { printf 'FPC not available (set FPC=path/to/fpc)\n' >&2; exit 127; }
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && { pwd -W 2>/dev/null || pwd; })
work=$repo/build/fpc-tests
mkdir -p "$work/units" "$work/bin" "$work/log"
if [ "$#" -gt 0 ]; then programs=$*
else
  programs=$(cd "$repo" && ls Tests/*.dpr Tests/Package2/*.dpr examples/Demos/Demo*.dpr examples/Showcase/*.dpr 2>/dev/null | grep -v "SystemJson")
fi
failed=0
for rel in $programs; do
  name=$(basename "${rel%.dpr}")
  dir=$(dirname "$repo/$rel")
  rm -rf "$work/units"; mkdir -p "$work/units"
  if ! "$FPC" -B -vew -Mdelphi -FU"$work/units" -FE"$work/bin" -Fu"$repo/src" -Fu"$repo/examples/Demos" -Fu"$dir" -Fu"$dir/Source" -Fi"$repo/src" "$repo/$rel" > "$work/log/$name.build.txt" 2>&1; then
    printf '%-30s BUILD FAILED  %s\n' "$name" "$(grep -m1 -E 'Error:|Fatal:' "$work/log/$name.build.txt")"
    failed=$((failed + 1)); continue
  fi
  (cd "$work/bin" && ./"$name" auto < /dev/null > "$work/log/$name.run.txt" 2>&1); code=$?
  result=$(grep -m1 -E 'RESULT|ABORTED|unhandled' "$work/log/$name.run.txt" | sed 's/^ *//')
  printf '%-30s exit=%-3s %s\n' "$name" "$code" "$result"
  [ "$code" -ne 0 ] && failed=$((failed + 1))
  case "$result" in *" 0 failed"*|"") ;; *) failed=$((failed + 1));; esac
done
printf '\n%s program(s) with problems\n' "$failed"
[ "$failed" -eq 0 ]
