#!/bin/bash
# Build a signed kernel cmdline addon for one device.
# The image stays identical for all machines, the device specific kernel
# parameters live in a small signed PE addon on that machine's ESP:
#   ./build-addon.sh x270
#   -> mkosi.output/x270.addon.efi
# Install on the target machine (systemd-stub picks up global addons):
#   mkdir -p /efi/loader/addons
#   cp x270.addon.efi /efi/loader/addons/
# Needs ukify + sbsign and the mkosi signing key in this directory.
set -euo pipefail

dev="${1:?usage: build-addon.sh <device>  (one of: $(ls addons/*.cmdline 2>/dev/null | xargs -n1 basename | sed 's/.cmdline//' | tr '\n' ' '))}"
cmdline="$(grep -hv '^#' "addons/$dev.cmdline" | tr '\n' ' ')"

mkdir -p mkosi.output
ukify build \
    --cmdline "$cmdline" \
    --secureboot-private-key mkosi.key \
    --secureboot-certificate mkosi.crt \
    --output "mkosi.output/$dev.addon.efi"

echo "built mkosi.output/$dev.addon.efi with: $cmdline"
