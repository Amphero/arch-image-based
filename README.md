# arch-image-based

Image-based Arch Linux, built with [mkosi](https://github.com/systemd/mkosi).
Derived from [ParticleOS](https://github.com/systemd/particleos)
(LGPL-2.1-or-later) and keeps its mechanics: you build the image yourself
and sign it with your own keys, /usr is dm-verity protected, boot is via
signed UKIs, updates come from your clone via systemd-sysupdate.

One image serves several machines. Device differences are not baked in,
they ship separately:

| Difference | Mechanism |
|---|---|
| kernel parameters (quirks, sleep, mitigations) | signed UKI addon on that machine's ESP, see below |
| extra packages (tlp, vendor tools) | signed sysext in /var/lib/extensions, planned (issues) |
| configuration and enabled services | plain /etc, per machine, survives updates |

## Differences from upstream

- Arch only, stock Arch packages, stable mkosi from the repos. OBS
  profiles, other distros, netboot and sway are removed.
- No ParticleOS branding, the system identifies as Arch Linux.
- The gnome and kde profiles carry the desktop plus its integration
  (gvfs, portals, thumbnailers, printing, remote desktop). User apps are
  left out, they come from Flathub (the flathub profile ships the
  remote). kde uses plasma-login-manager instead of sddm.
- The display managers are enabled and ordered after the first boot
  wizard, no manual enabling.
- Silent boot with the firmware logo (plymouth bgrt) for the main, live
  and installer entries. Factory reset, emergency and debug stay verbose.
- The boot does not wait for the network.
- swtpm profile for machines without a hardware TPM: LUKS auto-unlock
  via systemd's software TPM, state encrypted on the ESP. Validated in a
  VM (direct image boot and the full installer path, reboots unlock from
  the persisted state), not yet on real hardware. The enrollment binds
  no PCR policy, a software TPM never gets measured into; the protection
  comes from the boot-secret-encrypted TPM state, which only the signed
  UKI can obtain.

## Building

`pacman -S mkosi` is all you need. Configure in `mkosi.local.conf`:

```conf
[Config]
Profiles=desktop,gnome,flathub
# kde instead of gnome, add swtpm on machines without a TPM
```

Generate your signing key once with `mkosi genkey`, then build with
`mkosi -B -f`. Test in a VM with `mkosi vm` (`--console=gui` for
graphics, `[Runtime] TPM=no` in mkosi.local.conf to exercise the swtpm
path). Write to a USB drive with `mkosi burn /dev/<usb>`, boot it with
Secure Boot in setup mode and use the "Installer" entry. Details on
installation, smartcard keys and recovery keys are in the
[upstream README](https://github.com/systemd/particleos), everything
there applies here too.

## Per-device kernel cmdline

One cmdline file per device in `addons/`, built and signed with
`./build-addon.sh <device>`, installed on that machine's ESP:

```sh
./build-addon.sh t480
mkdir -p /efi/loader/addons
cp mkosi.output/t480.addon.efi /efi/loader/addons/
```

systemd-stub verifies the signature and appends the parameters to every
UKI on that machine. Current devices: x270, t480, tuxedo.

## Updating

Manually from any checkout:

```sh
mkosi -B -ff sysupdate -- update --reboot
```

Or self updating with the `autobuild` profile: the image then carries a
24G encrypted builder partition and a weekly timer that rebuilds the
frozen checkout on it with current packages and stages the result via
sysupdate. Activation happens on the next regular reboot, a failed boot
falls back automatically. Config changes stay manual and snapshotted:
`builder-update-config.sh`. One time setup per machine:
`builder-setup.sh`, then copy the signing key onto the partition. Note:
the key lives on the machine then, an attacker with root access could
sign images. A pkcs11 token avoids that, see the issues.

## Picking up upstream changes

No full merges, upstream changes get cherry-picked as needed:

```sh
git fetch upstream
git log upstream/main --oneline
git cherry-pick <commit>
```

## Status

Open work is tracked in the
[issues](https://github.com/Amphero/arch-image-based/issues).
