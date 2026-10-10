#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Helpers of the installer scripts, which run as root in the running
# Android system (mksh, toybox).
#
# Output protocol, read by systeminstallerd. One record per line, fields
# separated by tabs:
#
#   PROGRESS <percent> <text>
#   STAGE destructive        from here on, stopping leaves the target broken
#   ERROR <text>             the reason of a failure, before exiting with 1
#   SYSTEM, DISK, PART, INSTALL   probe results, see probe.sh
#
# Every other line is log.
#
# mksh has 32-bit arithmetic: sizes in bytes go through awk, the rest is in
# MiB or sectors.
#

SI_ETC=${SI_ETC:-/system_ext/etc/systeminstaller}
SI_GRUB=$SI_ETC/grub
SI_TMP=/mnt/systeminstaller
SI_MOUNTS=

si_progress() {
    printf 'PROGRESS\t%s\t%s\n' "$1" "$2"
}

si_stage() {
    printf 'STAGE\t%s\n' "$1"
}

si_die() {
    printf 'ERROR\t%s\n' "$*"
    exit 1
}

# si_calc <awk expression>: integer result
si_calc() {
    awk "BEGIN { printf \"%.0f\", $1 }"
}

# si_mib <bytes>: MiB, rounded up
si_mib() {
    awk "BEGIN { printf \"%.0f\", int(($1 + 1048575) / 1048576) }"
}

si_title() {
    v=$(getprop ro.lineage.build.version)
    if [ -n "$v" ]; then
        echo "LineageOS $v"
    else
        echo "Android $(getprop ro.build.version.release)"
    fi
}

si_device() {
    getprop ro.product.device
}

# Directory name of a beside installation, also used for file names
si_install_name() {
    echo "android-system-$(si_device | tr 'A-Z_' 'a-z-')"
}

# Kernel command line of the running system, without what depends on how
# it was booted
si_default_cmdline() {
    set -f
    out=
    for t in $(cat /proc/cmdline); do
        case $t in
        BOOT_IMAGE=* | initrd=* | androidboot.android_dir=* | androidboot.mount_*=* | androidboot.live=*) ;;
        *) out="$out $t" ;;
        esac
    done
    set +f
    echo "${out# }"
}

#
# Block devices
#

# Disks that can be installed to or read from
si_disks() {
    for d in /sys/block/*; do
        d=${d##*/}
        case $d in
        loop* | ram* | zram* | dm-* | md* | nbd* | mmcblk*boot* | mmcblk*rpmb | sr*) ;;
        *) echo "$d" ;;
        esac
    done
}

# si_partitions <disk>
si_partitions() {
    for p in /sys/block/"$1"/"$1"*; do
        [ -f "$p/partition" ] && echo "${p##*/}"
    done
}

# Everything that may hold a filesystem: partitions, disks without
# partitions, optical drives
si_filesystems() {
    for d in $(si_disks); do
        parts=$(si_partitions "$d")
        if [ -n "$parts" ]; then
            echo "$parts"
        else
            echo "$d"
        fi
    done
    for d in /sys/block/sr*; do
        [ -e "$d" ] && echo "${d##*/}"
    done
}

# si_disk_of <partition>: the disk, or the name itself for a disk
si_disk_of() {
    if [ -f "/sys/class/block/$1/partition" ]; then
        p=$(readlink -f "/sys/class/block/$1")
        p=${p%/*}
        echo "${p##*/}"
    else
        echo "$1"
    fi
}

# si_part_dev <disk> <number>: name of a partition
si_part_dev() {
    case $1 in
    *[0-9]) echo "${1}p$2" ;;
    *) echo "$1$2" ;;
    esac
}

# si_partname <partition>: GPT partition name
si_partname() {
    sed -n 's/^PARTNAME=//p' "/sys/class/block/$1/uevent" 2>/dev/null
}

# si_size <block device name>: bytes
si_size() {
    si_calc "$(cat "/sys/class/block/$1/size") * 512"
}

# si_wait_dev <name>: wait for the device node, up to 10 seconds
si_wait_dev() {
    i=0
    while [ ! -b "/dev/block/$1" ]; do
        [ "$i" -ge 20 ] && return 1
        sleep 0.5
        i=$((i + 1))
    done
}

# si_dev_of_path <path>: block device name of the filesystem holding it.
# For a mount point covered by an overlay (/vendor of the generic tree),
# the filesystem under the overlay.
si_dev_of_path() {
    dev=$((0x$(stat -c %D "$1")))
    major=$(((dev >> 8) & 0xfff))
    minor=$(((dev & 0xff) | ((dev >> 12) & 0xfff00)))
    majmin=$major:$minor
    if [ "$major" = 0 ]; then
        majmin=$(awk -v mp="$1" '
            { for (i = 7; $i != "-"; i++);
              if ($5 == mp && $(i + 1) != "overlay" && $3 !~ /^0:/) d = $3 }
            END { print d }' /proc/self/mountinfo)
        [ -n "$majmin" ] || return 1
    fi
    p=$(readlink -f "/sys/dev/block/$majmin") || return 1
    echo "${p##*/}"
}

# Disks with a mounted filesystem
si_busy_disks() {
    while read -r _ _ majmin _; do
        p=$(readlink -f "/sys/dev/block/$majmin" 2>/dev/null) || continue
        si_disk_of "${p##*/}"
    done </proc/self/mountinfo | sort -u
}

# si_blkid <device name> <TYPE|UUID|LABEL>
si_blkid() {
    blkid -s "$2" -o value "/dev/block/$1" 2>/dev/null
}

# si_fs_size <device or file>: bytes of the filesystem in it, or of the
# whole device for unknown ones
si_fs_size() {
    magic=$(od -A n -t x4 -j 1024 -N 4 "$1" | tr -d ' ')
    if [ "$magic" = e0f5e1e2 ]; then
        bits=$(od -A n -t u1 -j 1036 -N 1 "$1" | tr -d ' ')
        blocks=$(od -A n -t u4 -j 1060 -N 4 "$1" | tr -d ' ')
        si_calc "$blocks * 2 ^ $bits"
        return
    fi
    magic=$(od -A n -t x2 -j 1080 -N 2 "$1" | tr -d ' ')
    if [ "$magic" = ef53 ]; then
        blocks=$(od -A n -t u4 -j 1028 -N 4 "$1" | tr -d ' ')
        bits=$(od -A n -t u4 -j 1048 -N 4 "$1" | tr -d ' ')
        si_calc "$blocks * 1024 * 2 ^ $bits"
        return
    fi
    if [ -b "$1" ]; then
        blockdev --getsize64 "$1"
    else
        wc -c <"$1" | tr -d ' '
    fi
}

#
# Mounts, all under $SI_TMP and undone on exit
#

si_cleanup() {
    for m in $SI_MOUNTS; do
        umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null
        rmdir "$m" 2>/dev/null
    done
    SI_MOUNTS=
}
trap si_cleanup EXIT
trap 'exit 1' HUP INT TERM

# si_mount <device name, device or file> [rw]: mounts it, sets SI_MNT to
# the mount point and SI_FSTYPE
si_mount() {
    mkdir -p "$SI_TMP"
    m=$(mktemp -d "$SI_TMP/m.XXXXXX") || return 1
    opts=ro
    [ "$2" = rw ] && opts=rw
    [ -f "$1" ] && opts="$opts,loop"
    dev=$1
    [ -f "$dev" ] || [ -b "$dev" ] || dev=/dev/block/$1
    for t in ext4 f2fs vfat ntfs ntfs3 erofs iso9660 udf; do
        if mount -t "$t" -o "$opts" "$dev" "$m" 2>/dev/null; then
            SI_MNT=$m
            SI_FSTYPE=$t
            SI_MOUNTS="$m $SI_MOUNTS"
            return 0
        fi
    done
    rmdir "$m"
    return 1
}

# si_umount <mount point>
si_umount() {
    umount "$1" 2>/dev/null || umount -l "$1"
    rmdir "$1" 2>/dev/null
    new=
    for m in $SI_MOUNTS; do
        [ "$m" = "$1" ] || new="$new $m"
    done
    SI_MOUNTS=$new
}

# si_free <mount point>: free MiB
si_free() {
    df -k "$1" | awk 'NR == 2 { printf "%d", $4 / 1024 }'
}

# si_build_date <system partition device or system.img>: ro.build.date.utc
si_build_date() {
    si_mount "$1" || return 1
    for f in "$SI_MNT/system/build.prop" "$SI_MNT/build.prop"; do
        if [ -f "$f" ]; then
            sed -n 's/^ro\.build\.date\.utc=//p' "$f"
            break
        fi
    done
    si_umount "$SI_MNT"
}

# si_copy <source> <destination> <MiB> <percent from> <percent to> <text>
si_copy() {
    i=0
    while [ "$i" -lt "$3" ]; do
        dd if="$1" of="$2" bs=1048576 skip="$i" seek="$i" count=16 conv=notrunc 2>/dev/null ||
            si_die "Could not write $2"
        i=$((i + 16))
        [ "$i" -gt "$3" ] && i=$3
        si_progress $(($4 + ($5 - $4) * i / $3)) "$6"
    done
}
