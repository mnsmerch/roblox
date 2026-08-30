#!/usr/bin/env bash
# Runs the offline specs with the Luau CLI.
#
# The Luau CLI sandboxes io, so a spec cannot read module files itself. Each
# spec therefore declares what it needs with inject markers:
#
#   --@INJECT Name=path/to/file.lua Other=path/to/other.lua@
#
# and this script inlines each file as `local Name = (function() ... end)()`
# in the order given. Multiple markers per spec are allowed, so a spec can set
# up shims between injections.
#
# A spec can also ask for a file as TEXT rather than as code:
#
#   --@SOURCE Name=path/to/file.lua@
#
# which inlines it as `local Name = [==[ ... ]==]`. That exists for the one
# thing the specs otherwise cannot reach: wiring that lives inside a service's
# Start(), which needs a Roblox server to run. The first Studio run of this
# project found a coverage check measuring the wrong thing precisely there, so
# a crude source check beats no check.
#
# And a whole directory of sources at once:
#
#   --@TREE Name=src@
#
# which inlines every .lua file under that directory as
# `local Name = { ["relative/path.lua"] = [==[ ... ]==], ... }`. A spec can then
# assert something about EVERY file rather than a hand-listed handful, which is
# what a check like "no call site passes the wrong number of arguments" needs -
# the mistake is never in the file you thought to list.
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

# ── 1. Syntax-check every source file ───────────────────────────────────────
echo "== syntax"
syntax_fail=0
# `-name '*.lua'` and not '*.lua*': ProfileStore is vendored as ProfileStore.luau
# and is third-party. Syntax-checking somebody else's module tells us nothing we
# can act on, and a failure there would read as a failure of ours.
for f in $(find src -name '*.lua' | sort); do
  if out=$("$COMPILE" --binary "$f" 2>&1 >/dev/null) && [ -z "$out" ]; then
    echo "  ok   $f"
  else
    echo "  FAIL $f"; echo "$out"; syntax_fail=1
  fi
done
[ "$syntax_fail" -eq 0 ] || { echo; echo "SYNTAX ERRORS - aborting"; exit 1; }

# ── 2. Build and run each spec ──────────────────────────────────────────────
spec_fail=0
for spec in tests/*_spec.lua; do
  echo
  echo "== $(basename "$spec")"

  bundle=$(mktemp "/tmp/sad_$(basename "$spec" .lua)_XXXX.lua")

  while IFS= read -r line; do
    case "$line" in
      "--@INJECT "*)
        pairs="${line#--@INJECT }"; pairs="${pairs%@}"
        for pair in $pairs; do
          name="${pair%%=*}"
          path="${pair#*=}"
          echo "local $name = (function()"
          cat "$path"
          echo "end)()"
        done
        ;;
      "--@SOURCE "*)
        pairs="${line#--@SOURCE }"; pairs="${pairs%@}"
        for pair in $pairs; do
          name="${pair%%=*}"
          path="${pair#*=}"
          # A long-bracket level nothing in this codebase uses, so source
          # containing ]] or ]=] cannot close the literal early.
          echo "local $name = [=====["
          cat "$path"
          echo "]=====]"
        done
        ;;
      "--@TREE "*)
        pairs="${line#--@TREE }"; pairs="${pairs%@}"
        for pair in $pairs; do
          name="${pair%%=*}"
          root="${pair#*=}"
          echo "local $name = {"
          for f in $(find "$root" -name '*.lua' | sort); do
            echo "[\"$f\"] = [=====["
            cat "$f"
            echo "]=====],"
          done
          echo "}"
        done
        ;;
      *)
        printf '%s\n' "$line"
        ;;
    esac
  done < "$spec" > "$bundle"

  if "$LUAU" "$bundle"; then
    rm -f "$bundle"
  else
    echo "  (bundle kept for inspection: $bundle)"
    spec_fail=1
  fi
done

echo
[ "$spec_fail" -eq 0 ] && echo "ALL SPECS PASSED" || { echo "SPEC FAILURES"; exit 1; }
