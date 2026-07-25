#!/bin/bash
# Build a system extension against the current base image.
#   ./build-sysext.sh t480
#   -> mkosi.output/t480.sysext.raw
# Install on the target machine:
#   cp t480.sysext.raw /var/lib/extensions/
#   systemd-sysext refresh
# Needs the main image in mkosi.output/ first, it provides the base tree
# so only files not already in the image end up in the extension.
set -euo pipefail

name="${1:?usage: build-sysext.sh <name>  (one of: $(ls -d sysexts/*/ 2>/dev/null | xargs -n1 basename | tr '\n' ' '))}"
base="$PWD/mkosi.output/ArchLinux__x86-64.raw"
[ -e "$base" ] || { echo "build the main image first ($base is missing)"; exit 1; }

# The skeleton links /var/lib/pacman to the database the image keeps in
# /usr (see mkosi.conf.d/arch/mkosi.postinst). Without it pacman thinks
# the base tree is empty and pulls every dependency into the extension.
mkosi --directory "sysexts/$name" \
    --base-tree "$base" \
    --skeleton-tree "$PWD/sysexts/skeleton" \
    --output-directory "$PWD/mkosi.output" \
    --output "$name.sysext" \
    -f build

echo "built mkosi.output/$name.sysext.raw"
