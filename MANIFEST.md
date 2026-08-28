# Backup Manifest

`FILES-MANIFEST.tsv` contains one row for every included file, directory, and symlink. This document describes the inclusion groups and restore policy.

| Included path | Original location | Restore destination | Why included | Portable | Manual review | Sensitive |
|---|---|---|---|---|---|---|
| `packages/official-explicit.txt` | Pacman database | Package installation | Exact explicit official inventory | Reference | Yes, hardware packages | No |
| `packages/official-portable.txt` | Derived inventory | Pacman installation | Hardware-filtered automatic list | Yes | Normal package availability | No |
| `packages/aur-explicit.txt` | Pacman database | Yay installation | Explicit AUR/foreign inventory | Mostly | AUR trust and availability | No |
| `packages/flatpak-apps.txt` | Flatpak database | Flatpak installation | Application IDs only | Yes | Currently empty | No |
| `dotfiles/home/` | Selected files under `/home/zynx` | Restoring user’s home | Desktop, shell, editor and scripts | Yes | Keyboard/device preferences | Prayer coordinates removed |
| `assets/icons/` | `/home/zynx/.icons` | `~/.icons` | Exact cursor/icon appearance | Yes | Theme licensing | No |
| `assets/Pictures/Wallpapers/7.jpg` | Current wallpaper | `~/Pictures/Wallpapers/7.jpg` | Required by dynamic theme | Yes | Personal visual asset | No |
| `system-reference/etc/` | Selected `/etc` files | Reference; optional curated restore | Documents intentional system choices | Mixed | Required before use | Source UUIDs and hostname redacted/omitted |
| `system-reference/sddm-themes/` | Unmanaged active SDDM theme | `/usr/share/sddm/themes` | Reproduces login appearance | Yes | Test before reboot | No |
| `hardware/` | Runtime inspection commands | Documentation only | Source hardware and service reference | No | Never restore verbatim | Filesystem UUIDs and hostname redacted |
| `restore.sh` | New recovery workflow | Run from kit | Idempotent guided restoration | Yes | Review before privileged actions | No |

## Explicit Exclusions

Browser profiles, caches, credentials, SSH/GPG keys, authentication state, project repositories, personal documents, Downloads, Docker data, package caches, build outputs, histories, logs, coredumps, temporary files, inactive SDDM theme source, and hardware-generated service state are excluded.

The source’s `~/.config/gh/hosts.yml`, Claude state, Syncthing certificates, and project environment files were explicitly rejected as credential-bearing.
