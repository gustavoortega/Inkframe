#!/bin/bash
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
swiftc -O scripts/make-icon.swift -o "$work/make-icon"
"$work/make-icon" "$work/AppIcon.png"
set="$work/AppIcon.iconset"
mkdir "$set"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$work/AppIcon.png" --out "$set/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$work/AppIcon.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
