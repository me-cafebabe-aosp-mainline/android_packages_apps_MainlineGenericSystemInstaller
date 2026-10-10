#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# What gets installed is the running system:
#
# - system, system_dlkm, vendor, vendor_dlkm: the block devices mounted
#   at their mount points (loop devices of images, or partitions)
# - kernel and ramdisk: from the Android directory it was booted from,
#   found again by name, with the kernel release of the running kernel
# - firmware: the image mounted at /mnt/vendor/firmware, or the directory
#
# source_find sets:
#   SRC_system, SRC_system_dlkm, SRC_vendor, SRC_vendor_dlkm  device names
#   SRC_DIR, SRC_DIR_DEV, SRC_DIR_NAME  Android directory (mounted), its
#                                       device and its path on the device
#   SRC_FIRMWARE      device name of the firmware image, or empty
#   SRC_FIRMWARE_DIR  firmware directory, if not an image, or empty
#   SRC_MSG           why nothing was found, when it returns 1
#

# source_kernel_release <kernel>
source_kernel_release() {
    local off
    if [ "$(dd if="$1" bs=1 skip=514 count=4 2>/dev/null)" = HdrS ]; then
        # x86 boot protocol: kernel_version points to the version string
        off=$(od -A n -t u2 -j 526 -N 2 "$1" | tr -d ' ')
        dd if="$1" bs=1 skip=$((off + 512)) count=128 2>/dev/null | tr '\0' '\n' | head -n 1 | cut -d ' ' -f 1
    else
        grep -a -o -m 1 'Linux version [^ ]*' "$1" | cut -d ' ' -f 3
    fi
}

source_find_android_dir() {
    local release names fs n d
    release=$(uname -r)
    names="$(getprop ro.boot.android_dir) android boot/android"
    for fs in $(si_filesystems); do
        si_mount "$fs" || continue
        for n in $names; do
            d=$SI_MNT/$n
            if [ -f "$d/kernel" ] && [ -f "$d/ramdisk-all-combined.img" ] &&
                [ "$(source_kernel_release "$d/kernel")" = "$release" ]; then
                SRC_DIR=$d
                SRC_DIR_DEV=$fs
                SRC_DIR_NAME=$n
                return 0
            fi
        done
        si_umount "$SI_MNT"
    done
    return 1
}

source_find() {
    local root p dev fw
    SRC_MSG=
    root=$(si_dev_of_path /system) || {
        SRC_MSG="The system partition is not on a block device"
        return 1
    }
    for p in $LAYOUT_SYSTEM_PARTS; do
        eval "SRC_$p="
        if [ "$p" = system ]; then
            dev=$root
        else
            [ -d "/$p" ] || continue
            dev=$(si_dev_of_path "/$p") || continue
            # Not a mount, a directory of another partition
            [ "$dev" = "$root" ] && continue
        fi
        eval "SRC_$p=\$dev"
    done
    if [ -z "$SRC_vendor" ]; then
        SRC_MSG="The vendor partition is not on a block device"
        return 1
    fi

    if ! source_find_android_dir; then
        SRC_MSG="The kernel and ramdisk of the running system were not found"
        return 1
    fi

    SRC_FIRMWARE=
    SRC_FIRMWARE_DIR=
    fw=/mnt/vendor/firmware
    if [ -d "$fw" ]; then
        dev=$(si_dev_of_path "$fw" 2>/dev/null)
        case $dev in
        loop*) SRC_FIRMWARE=$dev ;;
        *) [ -n "$(ls -A "$fw" 2>/dev/null)" ] && SRC_FIRMWARE_DIR=$fw ;;
        esac
    fi
    return 0
}

# Disks holding what the running system was booted from
source_disks() {
    local p dev
    for p in $LAYOUT_SYSTEM_PARTS; do
        eval "dev=\$SRC_$p"
        case $dev in
        loop*) ;;
        ?*) si_disk_of "$dev" ;;
        esac
    done
    [ -n "$SRC_DIR_DEV" ] && si_disk_of "$SRC_DIR_DEV"
}

# MiB of the firmware, as an image
source_firmware_mib() {
    if [ -n "$SRC_FIRMWARE" ]; then
        si_mib "$(si_fs_size "/dev/block/$SRC_FIRMWARE")"
    elif [ -n "$SRC_FIRMWARE_DIR" ]; then
        du -sk "$SRC_FIRMWARE_DIR" | awk '{ printf "%d", $1 / 1024 * 1.2 + 16 }'
    else
        echo 0
    fi
}

# source_write_firmware <image to create>: returns 1 if there is none
source_write_firmware() {
    local mib
    if [ -n "$SRC_FIRMWARE" ]; then
        mib=$(si_mib "$(si_fs_size "/dev/block/$SRC_FIRMWARE")")
        dd if="/dev/block/$SRC_FIRMWARE" of="$1" bs=1048576 count="$mib" 2>/dev/null
    elif [ -n "$SRC_FIRMWARE_DIR" ]; then
        mib=$(source_firmware_mib)
        truncate -s "${mib}M" "$1" &&
            mke2fs -q -F -t ext4 -b 4096 -d "$SRC_FIRMWARE_DIR" "$1" 2>/dev/null
    else
        return 1
    fi
}
