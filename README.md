# arch-image-based

Image-based Arch Linux built with [mkosi](https://github.com/systemd/mkosi),
derived from [ParticleOS](https://github.com/systemd/particleos)
(LGPL-2.1-or-later). You build and sign the image yourself, /usr is
read-only and verity protected, updates install A/B and a failed boot
rolls back on its own.

Every machine builds its own image from the same repo. The desktop, the
Flathub setup and the weekly self rebuild are always in it, a machine
only picks what differs: GNOME or KDE and a few hardware profiles.
Kernel parameters per model are profiles as well, user apps are
flatpaks.

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

`mkosi.local.conf` only holds what differs per machine. The command
line has no effect on profiles, they have to be in this file:

```conf
[Config]
Profiles=gnome,t480,installer
```

| Profile     | When                                                  |
| ----------- | ----------------------------------------------------- |
| `gnome`     | GNOME, or                                             |
| `kde`       | KDE Plasma, exactly one of the two                    |
| `coreboot`  | machines on the custom coreboot/vboot firmware        |
| `swtpm`     | machines without a usable hardware TPM                |
| `tailscale` | Tailscale client and NetworkManager plugin            |
| `t480` …    | one device profile, see below                         |
| `installer` | the image you are going to burn to a stick            |

Desktop, Flathub and the self rebuild are not profiles, they live in
`mkosi.conf.d/` and are always on.

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

## Extra software

Software only some machines need is a profile in `mkosi.profiles/`,
`tailscale` and `coreboot` are examples. A unit is not enabled by the
preset after the first boot, so enable it with a static symlink in the
profile's `mkosi.extra/`:

```sh
usr/lib/systemd/system/multi-user.target.wants/foo.service -> ../foo.service
```

Packages that are not in the Arch repos go into `mkosi.packages/` at
the top of the repo as built packages. Since every machine builds its
own image, there is nothing to rebuild or install separately, and a
rollback always brings the matching software along.

### The coreboot profile

`coreboot` carries what a machine running the
[custom coreboot/vboot firmware](https://github.com/Amphero/coreboot-t480)
needs on the device side:

- `flashrom` for internal updates of the firmware regions
- `vbnv`, a copy of the firmware repo's `scripts/vbnv.py`, to steer the
  A/B slots: `show`, `try-next`, `boot-ok`, `arm-update`
- `vboot-boot-ok.service`, enabled statically, reports each successful
  boot. Without it the TPM rollback counter never moves and an armed
  trial slot always falls back
- a modules-load.d entry for the `nvram` module behind `/dev/nvram`,
  which vbnv reads the vboot block through
- `fwupd.conf` behind the `/etc/fwupd` factory symlink: local capsule
  cabs (`OnlyTrusted=false`, the firmware checks the PKCS#7 signature
  itself), no shim with your own Secure Boot keys, and the dual-battery
  power check
- a modprobe blacklist for the `spi-intel` driver. fwupd's Locked-MTD
  checks want block-protection bits in the flash chip, which the SMM
  capsule writer rules out. With no MTD device the checks do not apply,
  and internal flashrom talks PCI directly anyway

`cbmem`, the eventlog reader, is not in the Arch repos. Build it from
the fetched coreboot tree (`make -C util/cbmem`) and put it into
`mkosi.packages/` as a package and add it to the profile. Internal
flashing additionally needs `iomem=relaxed` on the kernel cmdline, put
it in the machine's addon for the flash, see below.

`fwupdx64.efi` is signed with the image's key at build time
(`mkosi.postinst.chroot`). `/usr` is immutable, so the firmware repo's
runtime `sbctl sign` step cannot work here. The machine's firmware has
to have the mkosi certificate enrolled, same as for the UKIs.
`fwupdmgr install` can race the ESP automount (gpt-auto, 120 s idle
timeout). When UDisks reports the partition as already mounted, trigger
the mount (`stat /efi/EFI`) or restart fwupd and retry.

vbnv expects the vboot non-volatile block at CMOS offset 0x26. That
holds for firmware built from the linked repo; check
`VBOOT_VBNV_OFFSET` before pointing it at anything else.

## Device specific kernel parameters

Each machine model is a profile that only adds kernel parameters, they
go straight into the signed UKI: `t480`, `x270`, `infinitybook`,
`aspire-e5`. A new model is one file:

```conf
# mkosi.profiles/foo/mkosi.conf
[Content]
KernelCommandLine=
        mem_sleep_default=deep
```

Signed addons in `/boot/loader/addons` are left for temporary
parameters, `debug` for a verbose boot or `flash` for `iomem=relaxed`
while flashing a coreboot machine:

```sh
./build-addon.sh flash
# on the machine, as root, and remove it again afterwards:
mkdir -p /boot/loader/addons
cp mkosi.output/flash.addon.efi /boot/loader/addons/
```

## Self updates

The machine rebuilds its image weekly with current packages and stages
it, the next reboot activates it. One time setup, as root on the
machine:

```sh
./builder-setup.sh
cp mkosi.key mkosi.crt /var/lib/builder/arch-image-based/
systemctl start image-rebuild
```

Checkout, package cache, build output and key live in
`/var/lib/builder`, a compressed subvolume on the encrypted root, so the
build shares the free space with the system instead of a fixed
partition.

The weekly build never changes the configuration. Config updates are
manual and take a snapshot first:

```sh
./builder-update-config.sh
```

## Power management

The desktop ships tlp and tlp-pd instead of power-profiles-daemon, on
every machine. tlp-pd serves the same D-Bus interface, so the power mode
menu in GNOME and KDE keeps working, and tlp's defaults need no config.
Switch by hand there or with `tlp performance | balanced | power-saver`.

Device tuning comes with the device profile: `t480` and `x270` carry
their drop-in in `/usr/lib/tlp.d` and link it into `/etc/tlp.d` via
tmpfiles, tlp only reads `/etc`. Being part of the image, it follows
updates and rollbacks and survives a factory reset. Local changes go
into a later drop-in such as `/etc/tlp.d/50-local.conf`.

## Swap

zswap compresses swapped pages in RAM first, what does not fit goes to
a sparse file on the encrypted root, set up the way GNOME OS does it: a
file of four times the RAM behind a loop device, enabled with discard
(`swapfile.service`). It only takes the disk space that is actually
written back and gives it back once the pages are freed. Installations
from before keep their swap partition in addition, until a reinstall.

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

Open work: [issues](https://github.com/Amphero/arch-image-based/issues).
