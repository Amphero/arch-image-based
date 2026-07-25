#!/bin/bash
# Build a system extension against a base image.
#   ./build-sysext.sh t480 [image.raw]
#   -> mkosi.output/t480_<image version>.sysext.raw
# Install on the target machine:
#   cp t480_<version>.sysext.raw /var/lib/extensions/
#   systemd-sysext refresh
# Without a second argument the newest image in mkosi.output is used. It
# provides the base tree, so only files not already in the image end up
# in the extension.
#
# The extension is tied to the image it was built against: systemd only
# merges it when the running image has the same version. Both slots can
# therefore keep their own extension, and a rollback loads the matching
# one instead of a mismatched extension.
set -euo pipefail

name="${1:?usage: build-sysext.sh <name> [image.raw]  (one of: $(ls -d sysexts/*/ 2>/dev/null | xargs -n1 basename | tr '\n' ' '))}"
base="${2:-$(ls -t "$PWD"/mkosi.output/ArchLinux*.raw 2>/dev/null | grep -v '\.usr-\|\.esp\.\|\.sysext\.' | head -1)}"
[ -n "$base" ] && [ -e "$base" ] || { echo "no base image, build the main image first or pass one"; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Give pacman the package database of the base image, which keeps it in
# /usr (see mkosi.conf.d/arch/mkosi.postinst) while pacman looks in
# /var/lib/pacman. Without it pacman thinks the base tree is empty and
# pulls every dependency into the extension. Real copy, symlinks trip
# over mkosi's own directory setup. Needs root, like disk image base
# trees in general.
mkdir -p "$work/db/var/lib/pacman"
systemd-dissect --copy-from "$base" /usr/lib/pacman/local "$work/db/var/lib/pacman/local"

systemd-dissect --copy-from "$base" /usr/lib/os-release "$work/os-release"
version=$(sed -n 's/^IMAGE_VERSION=//p' "$work/os-release" | tr -d '"')
[ -n "$version" ] || { echo "the base image has no IMAGE_VERSION, build it with -B or mkosi.version"; exit 1; }
out="${name}_${version}"
echo "base image: $base ($version)"

# mkosi keeps the fields we write here and fills in the rest.
d="$work/extra/usr/lib/extension-release.d"
mkdir -p "$d"
printf 'ID=arch\nSYSEXT_LEVEL=%s\n' "$version" >"$d/extension-release.$out"

mkosi --directory "sysexts/$name" \
    --base-tree "$base" \
    --skeleton-tree "$work/db" \
    --extra-tree "$work/extra" \
    --output-directory "$PWD/mkosi.output" \
    --output "$out" \
    --output-extension "sysext.raw" \
    -f build

echo "built mkosi.output/$out.sysext.raw"
