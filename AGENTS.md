# AGENTS.md - MainlineGenericSystemInstaller

Agents must read this file before touching anything in this repository.

Part of the mainline repository set. Map of all repos:
`vendor/mainline/docs/REPOSITORIES.md`.

The system installer of `device/mainline/generic`: installs the running
system (the live ISO, or an installed system) to a whole disk, beside
another operating system, or upgrades an installation. It also builds
the flashable disk image (`m diskimage`). Overview: `README.md`.

## Read first

| Task | Read |
|------|------|
| Anything | `README.md` |
| Commands and options of the scripts | `scripts/systeminstaller.sh` (header) |
| Output protocol of the scripts, helpers | `scripts/lib/common.sh` (header) |
| Where the installed files come from | `scripts/lib/source.sh` (header) |
| Probe records | `scripts/lib/probe.sh` (header) |
| Partition layout | `scripts/lib/layout.sh` |
| BIOS boot code | `scripts/lib/bootcode.sh` |
| The interface between app and daemon | `aidl/device/mainline/generic/installer/*.aidl` |
| Boot parameters it writes (`androidboot.mount_*`, `android_dir`) | `device/mainline/generic/docs/boot-parameters.md` |
| How `generic_init` finds what was installed | `vendor/mainline/services/generic_init/docs/DYNAMIC_MOUNT.md` |

## How it fits together

```
SystemInstaller (app, Kotlin, system UID)
    | ISystemInstaller (unstable AIDL, binder)
systeminstallerd (C++, root, lazy service started by servicemanager)
    | runs, reads tab separated lines from stdout
/system_ext/bin/systeminstaller (mksh) + /system_ext/etc/systeminstaller/lib/*.sh
    | uses
/system_ext/etc/systeminstaller/grub/ (GRUB images built by grub/Android.bp)
```

The scripts do all the work. The daemon only parses their output
(`PROGRESS`, `STAGE`, `ERROR`, `SYSTEM`, `DISK`, `PART`, `INSTALL`) into
AIDL results and callbacks. The app only asks and shows.

`scripts/lib/layout.sh`, `bootcode.sh` and `grubcfg.sh` are shared with
`scripts/make-diskimage.sh`, which runs on the build host (`/bin/sh`).
A whole disk installation with the default layout (partitions for
everything) and the disk image must stay identical.

## Hard rules

- No Android build, and no installation, without asking the human first
  (`hardware/mainline/common/docs/WORKFLOW.md`). An installation erases
  a disk or writes to a partition: only in the test environment the human
  named, after checking the target. The parts that run on the build host
  can be tested there (see below).
- Everything installs to `system_ext` (`system_ext_specific: true`).
- No `Android.mk`: Soong modules in `Android.bp`, build tasks in
  `build/tasks.mk` only.
- SELinux: labels only (`sepolicy/`). The device is permissive and the
  installer needs it; do not try to write a complete policy.
- The device scripts run on Android's mksh and toybox: POSIX sh, no
  bashisms, no GNU options. Check that a toybox applet supports an option
  before using it (`awk`, `sgdisk`, `mke2fs`, `newfs_msdos`, `blkid` are
  separate binaries in `/system/bin`).
- Every variable used inside a function is declared `local` on its first
  line. Shell functions share variables otherwise. Globals are uppercase:
  the options (`TARGET`, `CMDLINE`, `MOUNT_*`, `USERDATA_*`, `ANDROID_FS`,
  `SIZE_*`, `BOOT_ENTRIES`, `ALLOW_DOWNGRADE`, set by
  `systeminstaller.sh`), and the results of the libraries, prefixed by
  their file (`SI_*`, `SRC_*`, `MIB_*`, `LAYOUT_*`, `PART_*`, `DISK_*`,
  `BESIDE_*`, `INSTALL_*`). Functions are prefixed the same way.
- mksh has 32-bit arithmetic: never compute bytes in `$(( ))`. Use
  `si_calc` / `si_mib` (awk), and count in MiB or sectors.
- The shared libraries (`layout.sh`, `bootcode.sh`, `grubcfg.sh`) must
  also run on the host shell, and must not use helpers of `common.sh`.
- Mount only through `si_mount` / `si_umount`, under `/mnt/systeminstaller`:
  they are undone on exit. Never add a bind mount into another system's
  root to `SI_MOUNTS`: cleanup runs `rmdir` on the mount points.
- Print `STAGE destructive` before the first write to the target; the
  daemon refuses to cancel after it. Exit 1 after an `ERROR` line
  (`si_die`).
- Never write to the disk of the running system, nor to a disk with a
  mounted partition. Keep the checks of `disk_check`, `beside_open` and
  `probe`.
- A change to the output protocol changes the daemon parser and the AIDL
  parcelables in the same commit. The AIDL interface is unstable: change
  it freely, the app and the daemon are always built together.
- AIDL strings are `@utf8InCpp` and not nullable: the app must pass ""
  instead of null.
- The app is Jetpack Compose with `MaterialExpressiveTheme`. The
  Expressive components are experimental: before using one, read its
  signature in the sources jar of the material3 version in
  `prebuilts/sdk/current/androidx/m2repository/androidx/compose/material3/material3-android/`,
  not in the documentation of another version.
- The daemon accepts only the system UID (the app has
  `android:sharedUserId="android.uid.system"`).
- GRUB's `core.img` expects the EFI system partition as `gpt2`
  (`grub/mkgrub.sh`, `-p (,gpt2)/EFI/BOOT`): keep the BIOS boot partition
  first in `layout.sh`.
- New files start with the SPDX header (see any existing file).
- A change of behavior updates `README.md` in the same commit.
- Commit subjects start with the subdirectory name only (`scripts: ...`,
  `app: ...`, `daemon: ...`), or no prefix for top level files. Concise
  body, then the `Assisted-by:` trailers, see
  `hardware/mainline/common/docs/COMMIT_CONVENTIONS.md`.

## Layout

| Path | What |
|------|------|
| `app/` | `SystemInstaller`: `MainActivity.kt` (the steps), `Wizard.kt` (the choices and their rules, the request), `*Screen(s).kt` (the pages), `Ui.kt` (building blocks), `Installer.kt` (binder), `BootReceiver.kt` (launcher icon on `ro.boot.live=1`), Settings > System entry in `AndroidManifest.xml` |
| `aidl/` | `ISystemInstaller`, `IProgressCallback`, parcelables |
| `daemon/` | `systeminstallerd.cpp`, its `.rc` (lazy, `interface aidl`) |
| `scripts/systeminstaller.sh` | Entry point: `probe`, `install-disk`, `install-beside`, `upgrade`, the options |
| `scripts/lib/common.sh` | Protocol, block device, mount and size helpers |
| `scripts/lib/source.sh` | Finds what the running system was booted from |
| `scripts/lib/probe.sh` | Disks, partitions, installations, system info, serial ports, graphics devices |
| `scripts/lib/install.sh` | What both kinds of installation write: the system, the Android directory |
| `scripts/lib/disk.sh` | Whole disk installations and upgrades |
| `scripts/lib/beside.sh` | Installations beside another operating system, their boot entries |
| `scripts/lib/layout.sh`, `bootcode.sh`, `grubcfg.sh` | Shared with the disk image build |
| `scripts/make-diskimage.sh` | Disk image, on the build host |
| `grub/` | `mkgrub.sh` and genrules: GRUB images from `prebuilts/bootmgr` (filegroups in its `Android.bp`) |
| `build/tasks.mk` | `diskimage` target, included by `device/mainline/generic/build/tasks/40-installer.mk` |
| `installer.mk` | Packages and sepolicy dir, inherited by `device/mainline/generic/device.mk` |
| `sepolicy/` | Labels of the daemon and its service |

## Testing on the build host

Possible without Android:

- `bash grub/mkgrub.sh <out> <platform> grub/efi.cfg <files of prebuilts/bootmgr/lib64 and grub/linux-x86/<platform>>`
- `scripts/make-diskimage.sh` with host `sgdisk`, `mke2fs`, the prebuilt
  `mtools`, dummy images and any x86 kernel; boot the result with
  `qemu-system-x86_64` (BIOS, and OVMF for UEFI) and check the kernel
  command line on the serial console.
- Generated GRUB configurations: `grub-script-check` from
  `prebuilts/bootmgr`.
- Helpers of `common.sh` and `source.sh` that do not need root.

## Testing in a virtual machine

Only in one the human named (`hardware/mainline/common/docs/WORKFLOW.md`):

- Boot the live ISO with `androidboot.insecure_adb=true` added to its
  GRUB entry, and run `systeminstaller` as root over adb. The app runs
  the same script through the daemon.
- Before a destructive command, check that `systeminstaller probe` lists
  the disks of that virtual machine, and its DMI vendor
  (`/sys/class/dmi/id/sys_vendor`).
- Injected swipes may not scroll the app in a virtual machine;
  `input keyevent TAB` moves the focus and scrolls to it.

## Known gaps

- Android does not format empty user data yet: the installer formats
  `metadata` and `userdata` (partitions or images) itself.
- `userdata` of the disk image is not expanded on a bigger disk, and
  there is no unattended mode.
- GRUB on a shared EFI system partition is not registered in the
  firmware (no `efibootmgr`).
- The app does not reattach to an installation that runs when it is
  reopened.
