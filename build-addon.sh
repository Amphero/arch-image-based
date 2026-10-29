#!/bin/bash
# Build a signed kernel cmdline addon for temporary parameters. Device
# parameters are profiles, see mkosi.profiles/t480 and friends.
#   ./build-addon.sh flash
#   -> mkosi.output/flash.addon.efi
# Install on the machine (systemd-stub picks up global addons), remove
# it again when done:
#   mkdir -p /boot/loader/addons
#   cp flash.addon.efi /boot/loader/addons/
# Needs ukify + sbsign and the mkosi signing key in this directory.
set -euo pipefail

name="${1:?usage: build-addon.sh <name>  (one of: $(ls addons/*.cmdline 2>/dev/null | xargs -n1 basename | sed 's/.cmdline//' | tr '\n' ' '))}"
cmdline="$(grep -hv '^#' "addons/$name.cmdline" | tr '\n' ' ')"

mkdir -p mkosi.output
ukify build \
    --cmdline "$cmdline" \
    --secureboot-private-key mkosi.key \
    --secureboot-certificate mkosi.crt \
    --output "mkosi.output/$name.addon.efi"

echo "built mkosi.output/$name.addon.efi with: $cmdline"
