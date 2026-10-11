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
| Whole disk | A disk, erased | GPT, see [Whole disk layouts](#whole-disk-layouts). Boots with UEFI and BIOS. |
| Beside another operating system | An EXT4, F2FS or NTFS partition | Images in `/android-system-<device>` (`mount_system=imgs`). User data in directories (`mount_userdata=bind_mount_dir`), or in images (`mount_userdata=imgs`, `--userdata-images`, always on NTFS; `userdata.img` EXT4 or F2FS). Boot entries, see below. |
| Upgrade | An installation of either kind | Replaces the system, kernel, ramdisk and firmware, keeps the user data. Refuses an older build unless allowed. |

What gets installed is what the running system was booted from: the
block devices mounted at `/system`, `/vendor` and the `_dlkm` mount
points, and the kernel and ramdisk of its Android directory, found again
by name and by the release of the running kernel.

### Whole disk layouts

Each part chooses where it goes, as the `androidboot.mount_*` parameter
it sets:

| Part | Option | Values |
|------|--------|--------|
| System | `--system` | `std_parts` (partitions, default), `imgs`, `imgs_ram` |
| User data | `--userdata` | `std_parts` (partitions, default), `imgs` (`--userdata-size`), `bind_mount_dir` |
| Overlays | `--overlay` | none (default), `std_parts`, `imgs`, `imgs_ram`, `dirs` |

The partitions, in this order (`scripts/lib/layout.sh`):

| Partition | When | Default size |
|-----------|------|--------------|
| `bios` | BIOS boot code | 1 MiB |
| `efi` | Always: GRUB, and the Android directory without an `android` partition | Twice the content, at least 1 GiB |
| `system`, `system_dlkm`, `vendor`, `vendor_dlkm` | System partitions | Twice the content, at least 4 GiB, 128 MiB, 512 MiB, 512 MiB |
| `system_overlay`, `vendor_overlay` | Overlay partitions, those given a size (`--size system_overlay=<MiB>`) | none, empty EXT4 |
| `android` | Images or directories for the system or the user data: the Android directory `/android`, with the kernel (`--android-fs ext4` or `f2fs`) | Twice the content, at least 4 GiB, or the rest |
| `metadata`, `userdata` | User data partitions (`--userdata-fs ext4` or `f2fs`) | 64 MiB, the rest |

Sizes can be changed in the app (`--size`). The last partition takes the
rest. Without an `android` partition, the kernel, ramdisk and firmware
image are in `/android` of the EFI system partition; overlay images can
be added there later (`<partition>_overlay.img`), but not directories:
overlayfs refuses FAT32 directories. The `android` partition can be
written by another operating system: images and overlays of a USB drive
can be replaced there. Upgrades keep the layout and the parameters of
`grub.cfg`.

Every boot entry names the filesystem of the Android directory by its
UUID (`androidboot.android_dir_dev=UUID=`, as GRUB finds it): another
installation or media with an Android directory of the same name is not
used instead.

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
systeminstaller install-disk --target sdb --system imgs --userdata bind_mount_dir --overlay dirs
systeminstaller install-beside --target nvme0n1p3
systeminstaller install-beside --target nvme0n1p3 --userdata-images --userdata-size 16384
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
size of `userdata` in MiB (default 4096), and
`MAINLINE_GENERIC_DISKIMAGE_USERDATA_FS` its filesystem (`ext4`, default,
or `f2fs`). It is not expanded when the image is written to a bigger disk.

## Notes

- Android should format empty user data partitions and images on the
  first boot, but does not yet: the installer formats them as ext4.
- mksh has 32-bit arithmetic: sizes in bytes go through `awk`, the rest
  of the scripts counts in MiB or sectors.
- Android names block devices `/dev/block/<name>`, Linux `/dev/<name>`.
  For `update-grub` of a Linux system, its partition is mounted again
  from `/dev/<name>` and the chroot gets a `/dev` of a Linux system
  (`install_update_grub`), or its menu entries would get Android's paths.
- The BIOS boot code is installed by `lib/bootcode.sh`, which does what
  `grub-bios-setup` does: GRUB's `core.img` expects the EFI system
  partition as the second partition.
