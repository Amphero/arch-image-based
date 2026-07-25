# arch-image-based

Image-based Arch Linux, built with [mkosi](https://github.com/systemd/mkosi).
This is a derivative of [ParticleOS](https://github.com/systemd/particleos)
(LGPL-2.1-or-later) and keeps its mechanics: you build the image yourself
and sign it with your own keys, /usr is dm-verity protected, boots via
signed UKIs, updates come from your clone via systemd-sysupdate.

What is different from upstream:

- Arch only, using the stock Arch systemd. The OBS profiles, the other
  distro configs, the netboot image and sway are removed.
- No ParticleOS branding, the system identifies as what it is: Arch Linux.
- The gnome and kde profiles contain only the desktop core. Everything
  that exists as a flatpak is left out, install apps from Flathub
  yourself (the flathub profile preinstalls the remote).
- A swtpm profile for machines without a hardware TPM: LUKS auto-unlock
  via systemd's software TPM (systemd-tpm2-swtpm), state encrypted on
  the ESP. EXPERIMENTAL, not yet validated on real hardware.

## Building

Needs mkosi from the current main branch. Configure in `mkosi.local.conf`:

```conf
[Config]
Profiles=desktop,gnome,flathub
# no hardware TPM? add: swtpm
```

Generate your signing key once with `mkosi genkey`, then build with
`mkosi -B -f`. Write the image to a USB drive with `mkosi burn /dev/<usb>`,
boot it with Secure Boot in setup mode and use the "Installer" UKI
profile. Details on installation, smartcard keys and recovery keys are in
the [upstream README](https://github.com/systemd/particleos), everything
there applies here too.

## Updating

```sh
mkosi -B -ff sysupdate -- update --reboot
```

## Picking up upstream changes

No full merges, upstream changes get cherry-picked as needed:

```sh
git fetch upstream
git log upstream/main --oneline    # see what happened
git cherry-pick <commit>
```
