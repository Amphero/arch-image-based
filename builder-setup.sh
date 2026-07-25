#!/bin/bash
# One time setup of the builder partition on a machine running this
# image with the autobuild profile. Run as root after the first boot.
set -euo pipefail

d=/var/lib/builder
mountpoint -q "$d" || { echo "$d is not mounted (second boot needed after install)"; exit 1; }

btrfs subvolume create "$d/arch-image-based" 2>/dev/null || true
mkdir -p "$d/cache" "$d/output" "$d/snapshots"

if [ ! -e "$d/arch-image-based/mkosi.conf" ]; then
    git clone https://github.com/Amphero/arch-image-based "$d/arch-image-based"
fi

if [ ! -e "$d/arch-image-based/mkosi.local.conf" ]; then
    cat > "$d/arch-image-based/mkosi.local.conf" <<'EOF'
[Config]
# adjust to this machine: gnome or kde, swtpm only without a hardware TPM
Profiles=desktop,gnome,flathub,swtpm,autobuild

[Build]
CacheDirectory=/var/lib/builder/cache

[Output]
OutputDirectory=/var/lib/builder/output
EOF
fi

echo "done. still needed:"
echo "  1. copy mkosi.key and mkosi.crt into $d/arch-image-based/"
echo "  2. check the profiles in $d/arch-image-based/mkosi.local.conf"
echo "  3. first run: systemctl start image-rebuild"
