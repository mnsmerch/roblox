#!/usr/bin/env bash
# Runs the shared-module specs outside Roblox using the Luau CLI.
#
# The Luau CLI sandboxes io, so specs cannot read the module files themselves.
# This script therefore inlines each module into the spec at the
# --@INJECT_MODULES@ marker and runs the result.
set -euo pipefail

cd "$(dirname "$0")/.."

LUAU="${LUAU:-$(command -v luau || echo /tmp/luau)}"
if [ ! -x "$LUAU" ]; then
  echo "Luau CLI not found. Fetching..."
  tmp=$(mktemp -d)
  curl -sSL -o "$tmp/luau.zip" \
    "https://github.com/luau-lang/luau/releases/latest/download/luau-ubuntu.zip"
  unzip -oq "$tmp/luau.zip" -d /tmp
  chmod +x /tmp/luau /tmp/luau-compile
  LUAU=/tmp/luau
fi
COMPILE="$(dirname "$LUAU")/luau-compile"

MODULES="src/ReplicatedStorage/SAD_Shared/Modules"

# 1. Syntax-check every source file.
echo "== syntax"
fail=0
for f in $(find src -name '*.lua' | sort); do
  if out=$("$COMPILE" --binary "$f" 2>&1 >/dev/null) && [ -z "$out" ]; then
    echo "  ok   $f"
  else
    echo "  FAIL $f"; echo "$out"; fail=1
  fi
done
[ "$fail" -eq 0 ] || { echo "syntax errors"; exit 1; }

# 2. Build and run the spec bundle.
bundle=$(mktemp /tmp/sad_bundle_XXXX.lua)
trap 'rm -f "$bundle"' EXIT

while IFS= read -r line; do
  if [ "$line" = "--@INJECT_MODULES@" ]; then
    for m in Format TableUtil RNG Signal Trove; do
      echo "local $m = (function()"
      cat "$MODULES/$m.lua"
      echo "end)()"
    done
  else
    printf '%s\n' "$line"
  fi
done < tests/step1_spec.lua > "$bundle"

"$LUAU" "$bundle"
