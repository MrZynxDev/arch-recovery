# Source Hardware Reference

Documentation only. Do not replay these values on another machine.

- CPU: Intel Core i7-1165G7, 4 cores / 8 threads
- GPU: Intel Tiger Lake Iris Xe using `i915`
- Network: Intel Wi-Fi 6 AX201 using `iwlwifi`
- Storage: Intel SSD 670p NVMe
- Kernel at capture: Linux 7.1.8-arch1-3
- Root filesystem: Btrfs with `@`, `@home`, `@pkg`, and `@log` subvolumes
- Boot filesystem: VFAT mounted at `/boot`
- Swap: zram using zstd

The detailed command outputs retain useful filesystem and PCI layout information, but source filesystem UUIDs and the hostname are redacted. They are diagnostic references, not restore input.
