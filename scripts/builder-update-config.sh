#!/bin/bash
# Deliberate config update on a builder machine: snapshot the current
# state, then pull. The weekly rebuild never does this on its own.
set -euo pipefail

d=/var/lib/builder
ts=$(date +%Y%m%d-%H%M)
keep=2

btrfs subvolume snapshot -r "$d/arch-image-based" "$d/snapshots/$ts"
git -C "$d/arch-image-based" pull --ff-only

# Two, like the two slots on disk: the config the running image was
# built from and the one before it. Older ones are not free either, a
# snapshot pins whatever was in the checkout at the time, build output
# included.
for old in $(ls -1d "$d/snapshots"/* 2>/dev/null | sort | head -n -$keep); do
    btrfs subvolume delete "$old" >/dev/null
    echo "removed old snapshot $(basename "$old")"
done

echo "snapshot $d/snapshots/$ts created"
echo "rebuild now with: systemctl start image-rebuild"
