#!/bin/bash
# Build a system extension against a base image.
#   ./build-sysext.sh t480 [image.raw]
#   -> mkosi.output/t480.sysext.raw
# Install on the target machine:
#   cp t480.sysext.raw /var/lib/extensions/
#   systemd-sysext refresh
# Without a second argument the newest image in mkosi.output is used. It
# provides the base tree, so only files not already in the image end up
# in the extension. Extensions with kernel modules must be built against
# the image they will run on, see sysexts/displaylink.
set -euo pipefail

name="${1:?usage: build-sysext.sh <name> [image.raw]  (one of: $(ls -d sysexts/*/ 2>/dev/null | xargs -n1 basename | tr '\n' ' '))}"
base="${2:-$(ls -t "$PWD"/mkosi.output/ArchLinux*.raw 2>/dev/null | grep -v '\.usr-\|\.esp\.\|\.sysext\.' | head -1)}"
[ -n "$base" ] && [ -e "$base" ] || { echo "no base image, build the main image first or pass one"; exit 1; }
echo "base image: $base"

# Give pacman the package database of the base image, which keeps it in
# /usr (see mkosi.conf.d/arch/mkosi.postinst) while pacman looks in
# /var/lib/pacman. Without it pacman thinks the base tree is empty and
# pulls every dependency into the extension. Real copy, symlinks trip
# over mkosi's own directory setup. Needs root, like disk image base
# trees in general.
db=$(mktemp -d)
trap 'rm -rf "$db"' EXIT
mkdir -p "$db/var/lib/pacman"
systemd-dissect --copy-from "$base" /usr/lib/pacman/local "$db/var/lib/pacman/local"

mkosi --directory "sysexts/$name" \
    --base-tree "$base" \
    --skeleton-tree "$db" \
    --output-directory "$PWD/mkosi.output" \
    --output "$name" \
    --output-extension "sysext.raw" \
    -f build

echo "built mkosi.output/$name.sysext.raw"
