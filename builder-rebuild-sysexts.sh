#!/bin/bash
# Rebuild the extensions this machine has installed against the image
# that was just built, and drop the result next to the old one. Called
# by image-rebuild.service, can also be run by hand.
#
# Extensions are tied to an image version, so the old file has to stay:
# it is the one that loads if the new image fails and the machine falls
# back to the previous slot. Anything older than those two is removed.
set -euo pipefail

d=/var/lib/builder
ext=/var/lib/extensions
[ -d "$ext" ] || exit 0

base=$(ls -t "$d"/output/ArchLinux_*_*.raw 2>/dev/null | grep -v '\.usr-\|\.esp\.' | head -1)
[ -n "$base" ] || { echo "no image in $d/output"; exit 1; }

cd "$d/arch-image-based"

# The installed extensions, by name. Extensions built before the
# version binding have no suffix, take those along as well.
names=$(ls "$ext" 2>/dev/null | sed -n 's/\.sysext\.raw$//p' | sed 's/_[0-9]\{8,\}$//' | sort -u)
[ -n "$names" ] || exit 0

for name in $names; do
    [ -d "sysexts/$name" ] || { echo "no recipe for $name, skipping"; continue; }
    ./build-sysext.sh "$name" "$base"
    cp mkosi.output/"$name"_*.sysext.raw "$ext"/

    # An unversioned leftover would merge on any image, drop it.
    rm -f "$ext/$name.sysext.raw"
    # Keep the two newest, one per image slot.
    ls -t "$ext/$name"_*.sysext.raw | tail -n +3 | xargs -r rm -f
done

echo "extensions rebuilt, they take effect on the next boot"
