# Arch Recovery Kit

This repository reconstructs the portable parts of the source Arch Linux workstation: explicitly selected packages, Hyprland desktop configuration, terminal/editor preferences, themes, user scripts, and user services.

It is not a disk image. Boot, partitions, GPU drivers, hostname, machine identity, credentials, network secrets, and source storage identifiers are intentionally excluded or replaced with documentation placeholders.

## Quick Start

Start with a minimal, working Arch installation that has:

- A normal user with `sudo` access
- Working internet and DNS
- A mounted home directory
- A bootable kernel and bootloader already configured for the destination machine
- Git, or another way to download this kit

Then run:

```bash
cd Arch-Recovery
chmod +x restore.sh
./restore.sh --dry-run
./restore.sh
```

Use `./restore.sh --system-config` only after reading the system configuration section below. Use `--yes` to accept package and user-file prompts; safety-sensitive system groups still remain clearly logged.

The restore log and overwritten-file backups are stored under `~/.local/state/arch-recovery/`.

## What Is Restored

### Packages

- `packages/official-explicit.txt` is the exact explicit official-repository inventory from the source machine.
- `packages/official-portable.txt` is the automatic restore list with source-machine GPU/microcode packages removed.
- `packages/aur-explicit.txt` contains explicit foreign/AUR packages.
- `packages/flatpak-apps.txt` contains Flatpak application IDs. It is currently empty.
- `packages/required-additions.txt` contains dependencies referenced by the desktop config that were missing or not explicit on the source.
- `packages/hardware-review.txt` contains packages that require destination-hardware review.

The script performs a full Arch upgrade while installing official packages. If Yay is missing, it clones the official AUR package recipe into a temporary directory and builds it as the current user. AUR failures are reported without aborting unrelated restoration.

### User Configuration

The following are restored with automatic backups of conflicts:

- Hyprland and Hyprlock
- Waybar
- Awww/Matugen dynamic theme scripts and templates
- Kitty, Fuzzel, Wofi and Dunst
- GTK, Qt6ct and fontconfig preferences
- Fastfetch
- Bash and Vim preferences
- VS Code user settings and extension IDs
- Htop and Omniclicker preferences
- `~/.local/bin` utility scripts
- Dynamic-theme systemd user units
- Bibata cursor and BlackSur icon themes
- The currently selected wallpaper

Three stored paths use `__HOME__`. The restore script replaces that marker with the destination user’s actual home directory.

### Prayer-Time Location

The source Waybar script contained precise coordinates. They were deliberately removed from this Git-safe kit.

After restoration:

```bash
mkdir -p ~/.config/environment.d
cp ~/.config/environment.d/prayer.conf.example ~/.config/environment.d/prayer.conf
```

Edit `prayer.conf`, set `WAYBAR_PRAYER_LATITUDE` and `WAYBAR_PRAYER_LONGITUDE`, then log out and back in or restart the user manager and Waybar.

## System Configuration

`system-reference/` is primarily reference material. The normal restore mode does not apply it.

With `--system-config`, the script may offer to restore these reviewed groups, with backups:

- Locale and console keyboard preferences
- Zram generator policy
- Nier Automata SDDM theme and theme selector
- Generic DHCP networkd files for Ethernet, WLAN and WWAN

The network files assume `systemd-networkd`, `systemd-resolved`, and `iwd`. Do not apply them if the new machine uses NetworkManager unless you intentionally migrate network stacks.

The following files are documentation-only and are never automatically restored:

- `/etc/fstab`
- `/etc/kernel/cmdline`
- `/etc/mkinitcpio.conf`
- `/etc/mkinitcpio.d/linux.preset`
- `/etc/grub.d/15_uki`
- `/etc/conf.d/lm_sensors`
- `/etc/modules-load.d/ntsync.conf`
- `/etc/pacman.conf` and mirrorlist

The source hostname is deliberately omitted. Regenerate storage identifiers, fstab, initramfs and bootloader configuration on the destination. Merge desired Pacman options into the destination’s current file, and generate fresh geographically appropriate HTTPS mirrors.

## Hardware Migration

Review `hardware/` before selecting destination drivers. It records the source CPU, PCI devices, kernel, filesystems, mount layout, services, and graphics/network packages.

Do not infer that the new laptop needs Intel microcode or any specific Vulkan/Xorg driver. Install the microcode and graphics stack matching the destination CPU/GPU. Rerun sensor detection rather than restoring the source `lm_sensors` module list.

The source used Btrfs subvolumes and a UKI-oriented GRUB setup. These are examples, not a required destination layout.

## Services

The restore script enables these user services when available:

- `dynamic-theme.path`
- `dynamic-theme-watch.service`
- `syncthing.service`

System service state is recorded in `packages/system-services.txt` and `hardware/enabled-system-services.txt`. Enable destination-appropriate services rather than copying source enablement symlinks.

## Manual Checks After Restore

1. Install destination CPU microcode and GPU drivers from `packages/hardware-review.txt` as appropriate.
2. Verify Hyprland’s Lua configuration is supported by the installed Hyprland version.
3. Set the prayer-time location.
4. Review keyboard layouts and remove the example `epic-mouse-v1` device rule if unnecessary.
5. Confirm the Nier Automata SDDM theme works before rebooting into SDDM.
6. Configure Wi-Fi credentials locally with `iwctl`; no wireless credentials are backed up.
7. Configure printers, firewall policy, SSH keys, GPG keys, GitHub authentication, and application logins locally.
8. Review `system-reference/PACNEW-REVIEW.md` if present on a future refresh.

## Security and Git Safety

This kit intentionally excludes:

- SSH/GPG private keys and certificate stores
- Git, GitHub, Claude, Copilot, Netlify and application tokens
- Browser profiles, passwords, cookies, sessions and caches
- Shell/editor histories
- Syncthing device certificates and keys
- Project `.env` files and repositories
- Docker images, volumes and local databases
- Package/build caches, logs, coredumps and temporary data
- Downloads and personal documents

The source audit discovered credential-bearing GitHub CLI and Claude state. Those files are not included. Credentials should be revoked and regenerated if they may have been exposed elsewhere.

Before committing, run the validation commands in the next section. A private Git repository reduces exposure but is not a substitute for excluding secrets.

## Validation

```bash
bash -n restore.sh
./restore.sh --dry-run
git status --ignored
du -sh .
find . -type f -size +50M -print
```

`FILES-MANIFEST.tsv` inventories every included filesystem object. `SHA256SUMS` detects accidental changes after the kit is generated.

## Refreshing the Kit

Package lists and hardware reports are snapshots. Regenerate them after major package or desktop changes. Never refresh by copying all of `~/.config`, `~/.local`, or `/etc`; repeat the selective audit and secret scan instead.
