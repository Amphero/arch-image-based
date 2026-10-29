#!/bin/bash
# One time setup on an installed machine, as root after
# the first boot:
#   ./builder-setup.sh /path/to/keydir    (contains mkosi.key, mkosi.crt)
# Clones the repo into /var/lib/builder, takes over the profiles of
# the running image (minus installer) plus the device profile matching
# this machine, copies the key, adds a recovery
# key to root and starts the first rebuild.
set -euo pipefail

keydir="${1:?usage: builder-setup.sh <dir with mkosi.key and mkosi.crt>}"
d=/var/lib/builder
repo="$d/arch-image-based"
# tmpfiles creates the workspace subvolume on boot, compress what goes in
[ -d "$d" ] || btrfs subvolume create "$d"
btrfs property set "$d" compression zstd

btrfs subvolume create "$repo" 2>/dev/null || true
mkdir -p "$d/cache" "$d/output" "$d/snapshots"
[ -e "$repo/mkosi.conf" ] || git clone https://github.com/Amphero/arch-image-based "$repo"

if [ ! -e "$repo/mkosi.local.conf" ]; then
    profiles=$(tr ' ,' '\n\n' </usr/lib/arch-image-based/profiles 2>/dev/null | grep -vx -e installer -e '' || true)
    [ -n "$profiles" ] || profiles=gnome

    # The stick carries no device profile, pick it from the firmware's
    # DMI strings. If nothing matches, add it to mkosi.local.conf by hand.
    dmi=$(cat /sys/class/dmi/id/{sys_vendor,product_name,product_version,board_name} 2>/dev/null | tr '\n' ' ')
    case "$dmi" in
        *T480*)         device=t480 ;;
        *X270*)         device=x270 ;;
        *InfinityBook*) device=infinitybook ;;
        *E5-576*)       device=aspire-e5 ;;
        *)              device=; echo "no device profile matches: $dmi" ;;
    esac
    profiles=$(printf '%s\n' $profiles $device | sort -u | paste -sd,)

    cat >"$repo/mkosi.local.conf" <<CONF
[Config]
# gnome or kde, one device profile, plus coreboot, swtpm, tailscale
Profiles=$profiles

[Build]
CacheDirectory=$d/cache

[Output]
OutputDirectory=$d/output
CONF
    echo "profiles: $profiles"
fi

install -m 0600 "$keydir/mkosi.key" "$keydir/mkosi.crt" "$repo/"

# repart enrolls only the TPM. Without a second unlock method a cleared
# TPM, a new board or a damaged ESP (swtpm) loses root. Add a recovery
# key, once. Swap is a file on root, it needs none of its own.
for p in root; do
    dev="/dev/disk/by-partlabel/ArchLinux-$p"
    [ -e "$dev" ] || continue
    cryptsetup luksDump "$dev" | grep -q systemd-recovery && continue
    echo "recovery key for $p, write it down:"
    systemd-cryptenroll --unlock-tpm2-device=auto --recovery-key "$dev"
done

systemctl start --no-block image-rebuild.service
echo "first rebuild started: journalctl -fu image-rebuild"
