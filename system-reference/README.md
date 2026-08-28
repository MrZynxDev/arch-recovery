# System Configuration Reference

These files document the source installation. Only a small curated subset is offered by `restore.sh --system-config`, always with explanation and backups.

## Portable With Review

- `etc/systemd/network/20-*.network`: generic DHCP policy; only for systemd-networkd + iwd.
- `etc/systemd/zram-generator.conf`: portable compression policy with destination-dependent sizing.
- `etc/locale.conf`, `etc/locale.gen`, `etc/vconsole.conf`: language and keyboard preferences.
- `etc/sddm.conf.d/theme.conf` and `sddm-themes/nier-automata`: active SDDM theme.
- `etc/pacman.conf`: merge desired options into the destination version; do not overwrite.
- `etc/pacman.d/mirrorlist`: source-location snapshot; regenerate for the destination.

## Documentation Only

- `etc/fstab`: preserves Btrfs subvolume layout with source UUIDs redacted.
- `etc/kernel/cmdline`: preserves boot arguments with the source root PARTUUID redacted.
- `etc/mkinitcpio.conf` and `etc/mkinitcpio.d/linux.preset`: source initramfs/UKI strategy.
- `etc/grub.d/15_uki`: source-specific GRUB customization.
- `etc/conf.d/lm_sensors`: generated for the source Intel sensors.
- `etc/modules-load.d/ntsync.conf`: conditional compatibility module policy; likely unnecessary without Wine workloads.
- `etc/sddm.conf`: conflicting historical Silent-theme configuration, retained only to explain source state.

The source hostname is deliberately omitted. Never copy storage, boot, sensor, or GPU configuration verbatim to a different machine; generate destination UUIDs and boot configuration locally.

The orphaned `/etc/systemd/system/ollama.service.d/override.conf` was excluded. It would expose a future Ollama service on all network interfaces.
