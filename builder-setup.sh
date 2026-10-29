#!/bin/bash
# One time setup of the builder workspace on a machine running this
# image. Run as root after the first boot.
set -euo pipefail

d=/var/lib/builder
# tmpfiles creates the workspace subvolume on boot, compress what goes in
[ -d "$d" ] || btrfs subvolume create "$d"
btrfs property set "$d" compression zstd

btrfs subvolume create "$d/arch-image-based" 2>/dev/null || true
mkdir -p "$d/cache" "$d/output" "$d/snapshots"

if [ ! -e "$d/arch-image-based/mkosi.conf" ]; then
    git clone https://github.com/Amphero/arch-image-based "$d/arch-image-based"
fi

if [ ! -e "$d/arch-image-based/mkosi.local.conf" ]; then
    cat > "$d/arch-image-based/mkosi.local.conf" <<'EOF'
[Config]
# gnome or kde, one device profile, plus coreboot, swtpm, tailscale
Profiles=gnome,t480

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
