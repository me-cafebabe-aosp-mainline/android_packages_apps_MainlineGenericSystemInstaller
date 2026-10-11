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
| Whole disk | A disk, erased | GPT with the partitions of the chosen layout, GRUB for UEFI and BIOS |
| Beside another operating system | An EXT4, F2FS or NTFS partition | The system as images in `/android-system-<device>`, boot entries |
| Upgrade | An installation of either kind | Replaces the system, kernel, ramdisk and firmware, keeps the user data and the layout. Refuses an older build unless allowed |

What gets installed is what the running system was booted from: the
block devices mounted at `/system`, `/vendor` and the `_dlkm` mount
points, and the kernel and ramdisk of its Android directory, found again
by name and by the release of the running kernel.

Each boot entry passes how to mount everything (`androidboot.mount_*`),
and names the filesystem of the Android directory by its UUID
(`androidboot.android_dir_dev=UUID=`), so that another installation or
media with an Android directory is never used instead. See
`device/mainline/generic/docs/boot-parameters.md`.

### Whole disk

Each part chooses where it goes:

| Part | Option | Values |
|------|--------|--------|
| System | `--system` | `std_parts` (partitions, default), `imgs`, `imgs_ram` |
| User data | `--userdata` | `std_parts` (partitions, default), `imgs` (`--userdata-size`), `bind_mount_dir` (directories) |
| Overlays | `--overlay` | none (default), `std_parts`, `imgs`, `imgs_ram`, `dirs` |

The partitions, in this order (`scripts/lib/layout.sh`):

| Partition | When | Default size |
|-----------|------|--------------|
| `bios` | BIOS boot code | 1 MiB |
| `efi` | Always: GRUB, and the Android directory without an `android` partition | Twice the content, at least 1 GiB |
| `system`, `system_dlkm`, `vendor`, `vendor_dlkm` | System partitions | Twice the content, at least 4 GiB, 128 MiB, 512 MiB, 512 MiB |
| `system_overlay`, `vendor_overlay` | Overlay partitions, those given a size (`--size system_overlay=<MiB>`) | None: empty EXT4 |
| `android` | Images or directories for the system or the user data (`--android-fs ext4` or `f2fs`) | Twice the content, at least 4 GiB, or the rest |
| `metadata`, `userdata` | User data partitions (`--userdata-fs ext4` or `f2fs`) | 64 MiB, the rest |

Sizes can be changed in the app (`--size`). The last partition takes the
rest of the disk.

The Android directory `/android` holds the kernel, ramdisk and firmware
image, the system and user data images and directories, and the overlay
images and directories. It is on the `android` partition when there is
one. Otherwise it is on the EFI system partition, where overlay images
can be added later, but not directories: overlayfs refuses FAT32
directories.

### Beside another operating system

The system images, kernel, ramdisk and firmware image go to
`/android-system-<device>` of the partition (`mount_system=imgs`). The
user data in directories (`bind_mount_dir`), or in images (`imgs`,
`--userdata imgs`, always on NTFS).

On the partition of a Linux system, `--firmware linux` uses its firmware
directory (`usr/lib/firmware` or `lib/firmware`) instead of a firmware
image (`mount_firmware=all_possible_dirs`). It saves the space of the
image, and the Linux system keeps the files up to date. An upgrade keeps
the choice: no `firmware.img` on such a partition means its firmware.

Boot entries:

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
| `app/` | `SystemInstaller`, the interface (Kotlin, Jetpack Compose, Material 3 Expressive), see below |
| `aidl/` | `ISystemInstaller`, between the app and the daemon (unstable) |
| `daemon/` | `systeminstallerd`, runs the scripts as root. A lazy service: started by servicemanager when the app asks for it |
| `scripts/` | `systeminstaller` and its libraries, which do the work, see below |
| `scripts/make-diskimage.sh` | Builds the disk image on the build host, with the same layout and boot files |
| `grub/` | GRUB images, built from `prebuilts/bootmgr` |
| `sepolicy/` | Labels only: the installer needs a permissive device |
| `build/tasks.mk` | The `diskimage` build target, included by `device/mainline/generic` |
| `installer.mk` | Packages, inherited by `device/mainline/generic/device.mk` |

Everything is installed to `system_ext`.

The scripts:

| File | What |
|------|------|
| `systeminstaller.sh` | Commands and options, which become globals for the libraries |
| `lib/common.sh` | Output protocol, block device, mount and size helpers |
| `lib/source.sh` | What the running system was booted from |
| `lib/probe.sh` | Disks, partitions, installations, system info |
| `lib/install.sh` | What both kinds of installation write: the system, the Android directory |
| `lib/disk.sh` | Whole disk installations and upgrades |
| `lib/beside.sh` | Installations beside another operating system, their boot entries |
| `lib/layout.sh`, `lib/bootcode.sh`, `lib/grubcfg.sh` | Shared with the disk image build: partitions, BIOS boot code, GRUB configuration |

The app:

| File | What |
|------|------|
| `MainActivity.kt` | The steps, the calls to the daemon |
| `Wizard.kt` | The choices, the rules between them, the request |
| `ChoiceScreens.kt` | What to do, where, confirmation |
| `PartitionsScreen.kt` | Whole disk: layout and partition sizes |
| `OptionsScreen.kt` | Boot options (they edit the kernel command line), serial ports, user data |
| `ProgressScreens.kt` | Progress and result |
| `Ui.kt` | Building blocks, theme, formatting |
| `Installer.kt`, `BootReceiver.kt` | The binder service; the launcher icon on a live boot |

## Using it

- Live ISO (`androidboot.live=1`): launcher icon.
- Installed system: Settings > System > System installer.

The scripts can also be run directly, as root:

```
systeminstaller probe
systeminstaller install-disk --target sdb
systeminstaller install-disk --target sdb --system imgs --userdata bind_mount_dir --overlay dirs
systeminstaller install-beside --target nvme0n1p3
systeminstaller install-beside --target nvme0n1p3 --userdata imgs --userdata-size 16384
systeminstaller install-beside --target nvme0n1p3 --firmware linux
systeminstaller upgrade --target sdb
```

## Logs

- `systeminstallerd` writes the output of the last installation to
  `/data/system/systeminstaller.log` (in RAM on a live boot).
- The scripts copy it to the Android directory of the installation as
  `installer.log`. A failed installation may not get there.
- The app can save it anywhere (Save log), and its text can be copied.

## Disk image

`m diskimage` builds `<artifact prefix>-disk.img`, a whole disk
installation with partitions for everything.
`MAINLINE_GENERIC_DISKIMAGE_USERDATA_SIZE` sets the size of `userdata` in
MiB (default 4096), and `MAINLINE_GENERIC_DISKIMAGE_USERDATA_FS` its
filesystem (`ext4`, default, or `f2fs`). It is not expanded when the image
is written to a bigger disk.

## Notes

- Android should format empty user data partitions and images on the
  first boot, but does not yet: the installer formats them.
- mksh has 32-bit arithmetic: sizes in bytes go through `awk`, the rest
  of the scripts counts in MiB or sectors.
- Android names block devices `/dev/block/<name>`, Linux `/dev/<name>`.
  For `update-grub` of a Linux system, its partition is mounted again
  from `/dev/<name>` and the chroot gets a `/dev` of a Linux system
  (`beside_update_grub`), or its menu entries would get Android's paths.
- The BIOS boot code is installed by `lib/bootcode.sh`, which does what
  `grub-bios-setup` does. GRUB's `core.img` expects the EFI system
  partition as the second partition, and embeds everything it may need:
  there are no GRUB modules on the EFI system partition.
- Toybox `mount -o loop` leaves loop devices attached: `si_mount` attaches
  them itself and detaches them when unmounting.
- The `android` partition is formatted as F2FS without Android's features:
  GRUB does not find the files Linux writes on F2FS with `extra_attr`.
  User data (partitions and images) keeps them.
- FAT32 needs at least 65525 clusters: the EFI system partition is
  formatted with clusters of 4 KiB (512 bytes below 300 MiB).
