#!/bin/bash
# Deliberate config update on a builder machine: snapshot the current
# state, then pull. The weekly rebuild never does this on its own.
set -euo pipefail

d=/var/lib/builder
ts=$(date +%Y%m%d-%H%M)
keep=5

btrfs subvolume snapshot -r "$d/arch-image-based" "$d/snapshots/$ts"
git -C "$d/arch-image-based" tag "config/$ts" 2>/dev/null || true
git -C "$d/arch-image-based" pull --ff-only

# Keep the last few snapshots. They are cheap on their own, but they
# also pin whatever was in the checkout at the time, build output
# included, so an unbounded pile fills the partition.
for old in $(ls -1d "$d/snapshots"/* 2>/dev/null | sort | head -n -$keep); do
    btrfs subvolume delete "$old" >/dev/null
    git -C "$d/arch-image-based" tag -d "config/$(basename "$old")" >/dev/null 2>&1 || true
    echo "removed old snapshot $(basename "$old")"
done

echo "snapshot $d/snapshots/$ts and tag config/$ts created"
echo "rebuild now with: systemctl start image-rebuild"
