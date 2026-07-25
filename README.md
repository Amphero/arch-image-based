# arch-image-based

Image-based Arch Linux built with [mkosi](https://github.com/systemd/mkosi),
derived from [ParticleOS](https://github.com/systemd/particleos)
(LGPL-2.1-or-later). You build and sign the image yourself, /usr is
read-only and verity protected, updates install A/B and a failed boot
rolls back on its own. One image serves all machines, device differences
ship separately as signed addons and sysexts.

## Build

```sh
pacman -S mkosi
git clone https://github.com/Amphero/arch-image-based
cd arch-image-based
mkosi genkey
mkosi -B -f
```

Profiles go into `mkosi.local.conf`, pick `gnome` or `kde`, add `swtpm`
on machines without a hardware TPM, `autobuild` for self updates:

```conf
[Config]
Profiles=desktop,gnome,flathub,swtpm,autobuild
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

## Device specific kernel parameters

One cmdline file per device in `addons/` (currently x270, t480, tuxedo):

```sh
./build-addon.sh t480
# on the machine:
mkdir -p /efi/loader/addons
cp t480.addon.efi /efi/loader/addons/
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
manual and snapshotted first:

```sh
./builder-update-config.sh
```

## Manual update

```sh
mkosi -B -ff sysupdate -- update --reboot
```

## Notes

- User apps are not in the image, install them from Flathub.
- swtpm enrolls without a PCR policy, the protection comes from the
  boot-secret encrypted TPM state.
- With autobuild the signing key lives on the machine, see issue #6 for
  the pkcs11 alternative.
- Upstream changes: `git fetch upstream`, then cherry-pick.

Open work: [issues](https://github.com/Amphero/arch-image-based/issues).
