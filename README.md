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

Extensions add software to the read-only /usr without rebuilding the
image, one per purpose in `sysexts/`:

| name | contents |
| --- | --- |
| `tailscale` | tailscale and the NetworkManager plugin |
| `t480` | tlp, replaces power-profiles-daemon |

Build one against the image it will run on. This needs root, and the
image provides the base tree so only the new files end up in the
extension:

```sh
./build-sysext.sh tailscale mkosi.output/ArchLinux_<version>_x86-64.raw
```

Install it on the machine, as root:

```sh
cp tailscale_<version>.sysext.raw /var/lib/extensions/
systemd-sysext refresh
```

That merges it immediately, and `systemd-sysext.service` merges it again
on every boot. To check what is active, and to remove one again:

```sh
systemd-sysext status
rm /var/lib/extensions/tailscale_<version>.sysext.raw
systemd-sysext refresh
```

An extension only merges on the image it was built for, so both slots
can keep their own copy and a rollback picks up the matching one. With
the `autobuild` profile this is automatic: the weekly build rebuilds
every installed extension against the new image and keeps the two
newest, one per slot.

Services in an extension are started through symlinks in its own /usr,
so nothing has to be enabled by hand. The tailscale extension needs the
plugin package in `sysexts/tailscale/mkosi.packages/` before the build,
see [networkmanager-tailscale](https://github.com/Amphero/networkmanager-tailscale).

## Device specific kernel parameters

One cmdline file per device in `addons/`. The addon is signed with the
same key as the image, systemd-stub picks it up at boot:

```sh
./build-addon.sh t480
# on the machine, as root:
mkdir -p /boot/loader/addons
cp t480.addon.efi /boot/loader/addons/
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

## Notes

- User apps are not in the image, install them from Flathub.
- swtpm enrolls without a PCR policy, the protection comes from the
  boot-secret encrypted TPM state.
- With autobuild the signing key lives on the machine, in the encrypted
  builder partition.
- Upstream changes: `git fetch upstream`, then cherry-pick.

Open work: [issues](https://github.com/Amphero/arch-image-based/issues).
