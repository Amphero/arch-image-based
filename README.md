# arch-image-based

Image-based Arch Linux built with [mkosi](https://github.com/systemd/mkosi),
derived from [ParticleOS](https://github.com/systemd/particleos)
(LGPL-2.1-or-later). You build and sign the image yourself, /usr is
read-only and verity protected, updates install A/B and a failed boot
rolls back on its own.

The image is the same on all machines. Everything device specific stays
outside of it: kernel parameters as signed addons, extra software as
system extensions, user apps as flatpaks.

## Build

```sh
pacman -S mkosi
git clone https://github.com/Amphero/arch-image-based
cd arch-image-based
mkosi genkey
```

`mkosi genkey` creates the signing key. It is the key the machine will
trust for Secure Boot and verity, so keep it, and use a separate one per
machine if you do not want one key to be valid on all of them.

Profiles go into `mkosi.local.conf`, pick `gnome` or `kde`, add `swtpm`
on machines without a usable hardware TPM, `autobuild` for self updates,
and `installer` for the image you are going to burn to a stick. The
command line has no effect on profiles, they have to be in this file:

```conf
[Config]
Profiles=desktop,gnome,flathub,swtpm,autobuild,installer
```

`installer` adds the live and installer entries to the boot menu. An
installed system does not need them, and the config that
`builder-setup.sh` writes for the self updates leaves the profile out.

Then build:

```sh
mkosi -B -f
```

## Test in a VM

```sh
mkosi vm --console=gui
```

To exercise the swtpm path, add to `mkosi.local.conf`:

```conf
[Runtime]
TPM=no
```

## Install

```sh
mkosi burn /dev/<usb-stick>
```

Boot the stick with Secure Boot in setup mode and choose "Installer".
The first boot of the installed system creates the encrypted partitions
and asks for a user, then the login manager comes up.

## System extensions

Extensions add packages to the read-only /usr without rebuilding the
image, for software only some of your machines need. Write your own as
a directory under `sysexts/`, `sysexts/tailscale` and `sysexts/t480`
are two examples:

```conf
# sysexts/foo/mkosi.conf
[Distribution]
Distribution=arch

[Output]
Format=sysext
Overlay=yes

[Content]
Packages=
        foo
```

A unit in an extension is not enabled by the preset, symlink it in the
extension itself, in `sysexts/foo/mkosi.extra/`:

```sh
usr/lib/systemd/system/multi-user.target.wants/foo.service -> ../foo.service
```

The same trick masks something from the image, symlink it to
`/dev/null`. Packages that are not in the Arch repos go into
`sysexts/foo/mkosi.packages/` as built packages.

Build the extension against the image it will run on, as root:

```sh
./build-sysext.sh foo mkosi.output/ArchLinux_<version>_x86-64.raw
```

Install it on the machine, as root:

```sh
cp foo_<version>.sysext.raw /var/lib/extensions/
systemd-sysext refresh
```

`systemd-sysext.service` merges it again on every boot. To see what is
active, and to remove one:

```sh
systemd-sysext status
rm /var/lib/extensions/foo_<version>.sysext.raw
systemd-sysext refresh
```

An extension only merges on the image it was built for, so both slots
can keep their own copy and a rollback picks up the matching one.

With the `autobuild` profile the weekly build rebuilds the installed
extensions against the new image and keeps the two newest. It builds
what it finds a recipe for in `sysexts/`, so put yours there and bring
it onto the machine with `builder-update-config.sh`. An extension
without a recipe is left alone, which means it stops merging after the
next update, since it is built for the previous image.

### The coreboot extension

`sysexts/coreboot` carries what a machine running the
[custom coreboot/vboot firmware](https://github.com/Amphero/custom-coreboot-t480)
needs on the device side:

- `flashrom` for internal updates of the firmware regions
- `vbnv`, a copy of the firmware repo's `scripts/vbnv.py`, to steer the
  A/B slots: `show`, `try-next`, `boot-ok`, `arm-update`
- `vboot-boot-ok.service`, enabled statically, reports each successful
  boot - without it the TPM rollback counter never moves and an armed
  trial slot always falls back
- a modules-load.d entry for the `nvram` module behind `/dev/nvram`,
  which vbnv reads the vboot block through

`cbmem`, the eventlog reader, is not in the Arch repos. Build it from
the fetched coreboot tree (`make -C util/cbmem`) and put it into
`sysexts/coreboot/mkosi.packages/` as a package. Internal flashing
additionally needs `iomem=relaxed` on the kernel cmdline, which an
extension cannot set - put it in the machine's addon for the flash,
see below.

vbnv expects the vboot non-volatile block at CMOS offset 0x26. That
holds for firmware built from the linked repo; check
`VBOOT_VBNV_OFFSET` before pointing it at anything else.

## Device specific kernel parameters

The image ships one cmdline for everyone. Parameters a single machine
needs go into a file per machine in `addons/`, one parameter per line,
the files in there are examples:

```sh
# addons/foo.cmdline
i915.enable_fbc=1
mem_sleep_default=deep
```

The addon is signed with the same key as the image, systemd-stub picks
it up at boot:

```sh
./build-addon.sh foo
# on the machine, as root:
mkdir -p /boot/loader/addons
cp foo.addon.efi /boot/loader/addons/
```

## Self updates (autobuild profile)

The machine rebuilds its image weekly with current packages and stages
it, the next reboot activates it. One time setup, as root on the
machine:

```sh
./builder-setup.sh
cp mkosi.key mkosi.crt /var/lib/builder/arch-image-based/
systemctl start image-rebuild
```

The weekly build never changes the configuration. Config updates are
manual and take a snapshot first:

```sh
./builder-update-config.sh
```

## Update and rollback by hand

```sh
mkosi -B -ff sysupdate -- update --reboot
```

Both the old and the new version stay on disk and in the boot menu. To
go back, pick the older entry in the menu, or set it as the default:

```sh
bootctl list
bootctl set-default ArchLinux_<older version>_x86-64.efi
systemctl reboot
```

Careful: set-default pins that exact version, updates then no longer
become the default. Once done with the rollback, clear the pin, the
menu goes back to booting the newest image on its own:

```sh
bootctl set-default ""
```

## What a lost TPM costs you

Root, swap and the builder partition are encrypted against the TPM and
nothing else, `systemd-repart` enrolls no passphrase and no recovery
key. On a machine without a hardware TPM the swtpm profile keeps the
TPM state on the ESP, encrypted with a boot secret in an EFI variable.
Clearing the firmware, replacing the board or damaging the ESP
therefore takes those three partitions with it, and with them the
signing key if the machine builds its own images.

/home is a separate partition and not encrypted itself, systemd-homed
keeps every user in a password protected image inside it. User data is
the one thing that survives, and it can be opened on any other machine
with the user password.

So the worst case is a reinstall with a fresh key, and enrolling that
key in Secure Boot again. If you would rather have a way back, add a
second unlock method per machine, which leaves the TPM path untouched:

```sh
systemd-cryptenroll --recovery-key /dev/<root partition>
```

Note that the factory reset entry in the boot menu wipes root and home.
The builder partition survives it on purpose. The variant with TPM2
clear also resets the TPM for a reinstall with a fresh key, and storage
target mode exposes the whole disk over NVMe-TCP so another machine can
image it or rescue /home without a live stick.

## Notes

- User apps are not in the image, install them from Flathub.
- swtpm enrolls without a PCR policy, the protection comes from the
  boot-secret encrypted TPM state.
- With autobuild the signing key lives on the machine, in the encrypted
  builder partition.
- Upstream changes: `git fetch upstream`, then cherry-pick.

Open work: [issues](https://github.com/Amphero/arch-image-based/issues).
