#!/bin/bash
# Deliberate config update on a builder machine: snapshot the current
# state, then pull. The weekly rebuild never does this on its own.
set -euo pipefail

d=/var/lib/builder
ts=$(date +%Y%m%d-%H%M)

btrfs subvolume snapshot -r "$d/arch-image-based" "$d/snapshots/$ts"
git -C "$d/arch-image-based" tag "config/$ts" 2>/dev/null || true
git -C "$d/arch-image-based" pull --ff-only

echo "snapshot $d/snapshots/$ts and tag config/$ts created"
echo "rebuild now with: systemctl start image-rebuild"
