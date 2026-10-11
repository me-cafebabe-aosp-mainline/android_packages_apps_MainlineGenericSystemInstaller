#!/system/bin/sh
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Installs the running system. Run by systeminstallerd, as root.
#
# Usage:
#   systeminstaller probe
#   systeminstaller install-disk --target <disk> [options]
#   systeminstaller install-beside --target <partition> [options]
#   systeminstaller upgrade --target <disk or partition> [options]
#
# Options, and the globals they set for the libraries:
#
#   --cmdline <text>            CMDLINE: kernel command line without the
#                               boot method (default: the running one's)
#   --system std_parts|imgs|imgs_ram
#                               MOUNT_SYSTEM (install-disk, default std_parts)
#   --userdata std_parts|imgs|bind_mount_dir
#                               MOUNT_USERDATA (install-disk: default
#                               std_parts; install-beside: imgs or
#                               bind_mount_dir, default, and always imgs on NTFS)
#   --overlay std_parts|imgs|imgs_ram|dirs
#                               MOUNT_OVERLAY (install-disk, default none)
#   --userdata-fs ext4|f2fs     USERDATA_FS: userdata partition or image
#   --userdata-size <MiB>       USERDATA_SIZE: userdata image (16384)
#   --android-fs ext4|f2fs      ANDROID_FS: android partition (install-disk)
#   --firmware img|linux        FIRMWARE (install-beside, default img): a
#                               firmware image, or the firmware directory of
#                               the Linux system on the partition
#   --size <partition>=<MiB>    SIZE_<partition> (install-disk), see layout.sh
#   --no-boot-entries           BOOT_ENTRIES=0 (install-beside, upgrade)
#   --allow-downgrade           ALLOW_DOWNGRADE=1 (upgrade)
#

SI_ETC=${SI_ETC:-/system_ext/etc/systeminstaller}
for lib in common layout bootcode grubcfg source probe install disk beside; do
    . "$SI_ETC/lib/$lib.sh"
done

# opt_choice <option> <value> <allowed values...>: dies unless allowed
opt_choice() {
    local option value v
    option=$1
    value=$2
    shift 2
    for v in "$@"; do
        [ "$v" = "$value" ] && return 0
    done
    si_die "Unknown value $value of $option"
}

command=$1
[ $# -gt 0 ] && shift
TARGET=
CMDLINE=
MOUNT_SYSTEM=
MOUNT_USERDATA=
MOUNT_OVERLAY=
USERDATA_FS=ext4
USERDATA_SIZE=16384
ANDROID_FS=ext4
FIRMWARE=img
BOOT_ENTRIES=1
ALLOW_DOWNGRADE=0
disk_only=
while [ $# -gt 0 ]; do
    case $1 in
    --target) TARGET=$2; shift ;;
    --cmdline) CMDLINE=$2; shift ;;
    --system)
        opt_choice "$1" "$2" std_parts imgs imgs_ram
        MOUNT_SYSTEM=$2
        disk_only="$disk_only $1"
        shift
        ;;
    --userdata)
        opt_choice "$1" "$2" std_parts imgs bind_mount_dir
        MOUNT_USERDATA=$2
        shift
        ;;
    --overlay)
        opt_choice "$1" "$2" std_parts imgs imgs_ram dirs
        MOUNT_OVERLAY=$2
        disk_only="$disk_only $1"
        shift
        ;;
    --userdata-fs)
        opt_choice "$1" "$2" ext4 f2fs
        USERDATA_FS=$2
        shift
        ;;
    --userdata-size) USERDATA_SIZE=$2; shift ;;
    --android-fs)
        opt_choice "$1" "$2" ext4 f2fs
        ANDROID_FS=$2
        disk_only="$disk_only $1"
        shift
        ;;
    --firmware)
        opt_choice "$1" "$2" img linux
        FIRMWARE=$2
        [ "$command" = install-beside ] || si_die "Only for install-beside: $1"
        shift
        ;;
    --size)
        opt_choice "$1" "${2%%=*}" efi system system_dlkm vendor vendor_dlkm metadata android \
            system_overlay vendor_overlay
        eval "SIZE_${2%%=*}=\${2#*=}"
        disk_only="$disk_only $1"
        shift
        ;;
    --no-boot-entries) BOOT_ENTRIES=0 ;;
    --allow-downgrade) ALLOW_DOWNGRADE=1 ;;
    *) si_die "Unknown option $1" ;;
    esac
    shift
done
[ -n "$CMDLINE" ] || CMDLINE=$(si_default_cmdline)
if [ "$command" != install-disk ] && [ -n "$disk_only" ]; then
    si_die "Only for install-disk:$disk_only"
fi

case $command in
probe)
    probe
    ;;
install-disk)
    MOUNT_SYSTEM=${MOUNT_SYSTEM:-std_parts}
    MOUNT_USERDATA=${MOUNT_USERDATA:-std_parts}
    disk_install "$TARGET"
    ;;
install-beside)
    MOUNT_USERDATA=${MOUNT_USERDATA:-bind_mount_dir}
    [ "$MOUNT_USERDATA" = std_parts ] && si_die "User data partitions are only for install-disk"
    beside_install "$TARGET"
    ;;
upgrade)
    if [ -f "/sys/class/block/$TARGET/partition" ]; then
        beside_upgrade "$TARGET"
    else
        disk_upgrade "$TARGET"
    fi
    ;;
*)
    si_die "Unknown command $command"
    ;;
esac
