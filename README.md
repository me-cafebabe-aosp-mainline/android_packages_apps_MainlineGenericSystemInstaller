# System installer

Installs the running system of `device/mainline/generic` to a disk. The
running system can be the live ISO, or an installed system.

```
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
```

## What it does

| Mode | Target | Result |
|------|--------|--------|
| Whole disk | A disk, erased | GPT with the partitions `bios` (BIOS boot), `efi` (EFI system), `system`, `system_dlkm`, `vendor`, `vendor_dlkm`, `metadata` and `userdata` (`mount_system=std_parts`). Sizes can be changed in the app (`--size`); by default twice the content, at least 1 GiB, 4 GiB, 128 MiB, 512 MiB, 512 MiB and 64 MiB, `userdata` takes the rest, as EXT4 or F2FS (`--userdata-fs`). Kernel, ramdisk and firmware image in `/android` of the EFI system partition. Boots with UEFI and BIOS. |
| Beside another operating system | An ext4, F2FS or NTFS partition | Images in `/android-system-<device>` (`mount_system=imgs`). User data in directories, on NTFS in images (`userdata.img` EXT4 or F2FS). Boot entries, see below. |
| Upgrade | An installation of either kind | Replaces the system, kernel, ramdisk and firmware, keeps the user data. Refuses an older build unless allowed. |

What gets installed is what the running system was booted from: the
block devices mounted at `/system`, `/vendor` and the `_dlkm` mount
points, and the kernel and ramdisk of its Android directory, found again
by name and by the release of the running kernel.

Boot entries of an installation beside another operating system:

- UEFI: GRUB in `\EFI\android-system-<device>` of the EFI system partition
  of the same disk. It is not registered in the firmware: choose it in its
  boot menu.
- A Linux system on the same partition: a script in its `/etc/grub.d`,
  then its `update-grub` (or `grub2-mkconfig`) run in a chroot. If that
  fails, the entries go to `/boot/grub/custom.cfg` or
  `/boot/grub2/custom.cfg` instead.

The filesystem must be directly on a partition or disk (`generic_init`
does not find it on LVM or LUKS), and Secure Boot must be off.

## Layout

| Path | Content |
|------|---------|
| `app/` | `SystemInstaller`, the interface (Kotlin, Jetpack Compose, Material 3 Expressive) |
| `aidl/` | `ISystemInstaller`, between the app and the daemon (unstable) |
| `daemon/` | `systeminstallerd`, runs the scripts as root. A lazy service: started by servicemanager when the app asks for it |
| `scripts/` | `systeminstaller` and its libraries, which do the work. The output protocol is described in `lib/common.sh` |
| `scripts/make-diskimage.sh` | Builds the disk image on the build host, with the same layout and boot files |
| `grub/` | GRUB images, built from `prebuilts/bootmgr` |
| `sepolicy/` | Labels only: the installer needs a permissive device |
| `build/tasks.mk` | The `diskimage` build target, included by `device/mainline/generic` |
| `installer.mk` | Packages, inherited by `device/mainline/generic/device.mk` |

Everything is installed to `system_ext`.

## Using it

- Live ISO (`androidboot.live=1`): launcher icon.
- Installed system: Settings > System > System installer.

The scripts can also be run directly, as root:

```
systeminstaller probe
systeminstaller install-disk --target sdb
systeminstaller install-beside --target nvme0n1p3 --userdata-size 16384
systeminstaller upgrade --target sdb
```

## Logs

- `systeminstallerd` writes the output of the last installation to
  `/data/system/systeminstaller.log` (in RAM on a live boot).
- The scripts copy it to the target as `installer.log`: in `/android` of
  the EFI system partition, or in the Android directory beside another
  operating system. A failed installation may not get there.
- The app can save it anywhere (Save log), and its text can be copied.

## Disk image

`m diskimage` builds `<artifact prefix>-disk.img`, the layout of a whole
disk installation. `MAINLINE_GENERIC_DISKIMAGE_USERDATA_SIZE` sets the
size of `userdata` in MiB (default 4096). It is not expanded when the
image is written to a bigger disk.

## Notes

- Android should format empty user data partitions and images on the
  first boot, but does not yet: the installer formats them as ext4.
- mksh has 32-bit arithmetic: sizes in bytes go through `awk`, the rest
  of the scripts counts in MiB or sectors.
- The BIOS boot code is installed by `lib/bootcode.sh`, which does what
  `grub-bios-setup` does: GRUB's `core.img` expects the EFI system
  partition as the second partition.
