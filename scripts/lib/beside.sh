#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Installations beside another operating system: images in
# /android-system-<device> of an EXT4, F2FS or NTFS partition
# (mount_system=imgs), the user data in directories or, always on NTFS, in
# images. Boot entries: GRUB on the EFI system partition of the disk, and
# the GRUB menu of a Linux system on the partition.
#

# beside_find_esp <disk>: the EFI system partition of a disk
beside_find_esp() {
    local p n
    for p in $(si_partitions "$1"); do
        n=$(cat "/sys/class/block/$p/partition")
        if sgdisk --info="$n" "/dev/block/$1" 2>/dev/null | grep -qi 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B'; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

# beside_linux_firmware <mount point>: whether it has the firmware
# directory of a Linux system, one generic_init finds
beside_linux_firmware() {
    local d
    for d in usr/lib/firmware lib/firmware; do
        [ -n "$(ls -A "$1/$d" 2>/dev/null)" ] && return 0
    done
    return 1
}

# beside_linux_dev <directory>: fills it like /dev of a Linux system:
# block devices as /dev/<name> and /dev/disk/by-*, not /dev/block/<name>
# like Android, which grub-mkconfig would write to the menu entries
beside_linux_dev() {
    local b n v
    mkdir -p "$1/disk/by-uuid" "$1/disk/by-partuuid" "$1/pts" "$1/shm"
    for n in null:1:3 zero:1:5 full:1:7 random:1:8 urandom:1:9 tty:5:0; do
        mknod -m 0666 "$1/${n%%:*}" c $(echo "${n#*:}" | tr : ' ')
    done
    ln -s /proc/self/fd "$1/fd"
    ln -s /proc/self/fd/0 "$1/stdin"
    ln -s /proc/self/fd/1 "$1/stdout"
    ln -s /proc/self/fd/2 "$1/stderr"
    for b in /sys/class/block/*; do
        n=${b##*/}
        mknod -m 0660 "$1/$n" b $(tr : ' ' <"$b/dev") || continue
        v=$(si_blkid "$n" UUID)
        [ -n "$v" ] && ln -sf "../../$n" "$1/disk/by-uuid/$v"
        v=$(si_blkid "$n" PARTUUID)
        [ -n "$v" ] && ln -sf "../../$n" "$1/disk/by-partuuid/$v"
    done
}

# beside_update_grub <partition> <root of a Linux system on it>:
# regenerates its grub.cfg
#
# grub-mkconfig finds the root device in /proc/self/mountinfo, where it is
# the device the partition was mounted from: it is mounted again from
# /dev/<name> for that, and the chroot gets a /dev of a Linux system.
beside_update_grub() {
    local r fstype dev node created root bound n rc t b
    r=$2
    if [ -x "$r/usr/sbin/update-grub" ]; then
        set -- "$1" /usr/sbin/update-grub
    elif [ -x "$r/usr/sbin/grub2-mkconfig" ] && [ -f "$r/boot/grub2/grub.cfg" ]; then
        set -- "$1" /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
    elif [ -x "$r/usr/sbin/grub-mkconfig" ] && [ -f "$r/boot/grub/grub.cfg" ]; then
        set -- "$1" /usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg
    else
        return 1
    fi
    fstype=$(awk -v mp="$r" '
        { for (i = 7; $i != "-"; i++);
          if ($5 == mp) t = $(i + 1) }
        END { print t }' /proc/self/mountinfo)
    [ -n "$fstype" ] || return 1

    dev=$(mktemp -d "$SI_TMP/dev.XXXXXX") || return 1
    if ! mount -t tmpfs -o mode=0755 tmpfs "$dev"; then
        rmdir "$dev"
        return 1
    fi
    SI_MOUNTS="$dev $SI_MOUNTS"
    beside_linux_dev "$dev"

    # Android has no /dev/<name>: created only to be the mount source
    node=/dev/$1
    created=0
    if [ ! -e "$node" ]; then
        mknod -m 0600 "$node" b $(tr : ' ' <"/sys/class/block/$1/dev") || return 1
        created=1
    fi
    root=$(mktemp -d "$SI_TMP/root.XXXXXX") || return 1
    rc=1
    if mount -t "$fstype" "$node" "$root"; then
        SI_MOUNTS="$root $SI_MOUNTS"
        rc=0
    fi
    [ "$created" = 1 ] && rm -f "$node"
    if [ "$rc" != 0 ]; then
        rmdir "$root"
        si_umount "$dev"
        return 1
    fi

    bound=
    n=0
    rc=1
    for t in dev:"$dev" proc:/proc sys:/sys; do
        mount --bind "${t#*:}" "$root/${t%%:*}" || break
        bound="$root/${t%%:*} $bound"
        n=$((n + 1))
    done
    if [ "$n" = 3 ]; then
        shift
        PATH=/usr/sbin:/usr/bin:/sbin:/bin chroot "$root" "$@" && rc=0
    fi
    for b in $bound; do
        umount "$b" || umount -l "$b"
    done
    si_umount "$root"
    si_umount "$dev"
    return $rc
}

# beside_linux_grub <partition> <root of a Linux system on it> <title>
# <menu entries>: adds the entries to its GRUB menu
beside_linux_grub() {
    local part r name script cfgdir d begin end
    part=$1
    r=$2
    shift
    name=$(si_install_name)
    script=$r/etc/grub.d/35_$name
    {
        printf '#!/bin/sh\n# Added by the installer of %s\n' "$2"
        echo "cat <<'EOF'"
        printf '%s\n' "$3"
        echo EOF
    } >"$script"
    chmod 0755 "$script"
    if beside_update_grub "$part" "$r"; then
        echo "Added to the GRUB menu of the Linux system on this partition"
        return 0
    fi
    rm -f "$script"

    # Could not regenerate grub.cfg: custom.cfg, which grub.cfg includes
    cfgdir=
    for d in boot/grub2 boot/grub; do
        if [ -f "$r/$d/grub.cfg" ]; then
            cfgdir=$r/$d
            break
        fi
    done
    if [ -z "$cfgdir" ]; then
        echo "The GRUB configuration of the Linux system is not on this partition"
        return 1
    fi
    begin="### BEGIN $name ###"
    end="### END $name ###"
    [ -f "$cfgdir/custom.cfg" ] && sed -i "/^$begin\$/,/^$end\$/d" "$cfgdir/custom.cfg"
    {
        echo "$begin"
        printf '%s\n' "$3"
        echo "$end"
    } >>"$cfgdir/custom.cfg"
    echo "Added to ${cfgdir#"$r"}/custom.cfg of the Linux system on this partition"
}

# beside_entries <partition> <mount point> <title> <kernel command
# line> <userdata mount method> <GRUB filesystem module>
beside_entries() {
    local name entries added esp d
    name=$(si_install_name)
    entries=$(grubcfg_entries "$3" "$(si_blkid "$1" UUID)" "$6" "$name" "$4" "$5")
    added=0

    if [ -d /sys/firmware/efi ] && esp=$(beside_find_esp "$(si_disk_of "$1")") &&
        si_mount "$esp" rw; then
        d=$SI_MNT/EFI/$name
        mkdir -p "$d"
        install_grub_efi "$d" named
        {
            grubcfg_header
            printf '%s\n' "$entries"
        } >"$d/grub.cfg"
        sync
        # Not echo: mksh's interprets the backslashes
        printf 'Added GRUB as \\EFI\\%s on the EFI system partition: choose it in the boot menu of the firmware\n' "$name"
        si_umount "$SI_MNT"
        added=1
    fi

    if [ -d "$2/etc/grub.d" ] && beside_linux_grub "$1" "$2" "$3" "$entries"; then
        added=1
    fi

    [ "$added" = 1 ] || echo "No boot entry was added: add one by hand"
}

# beside_open <partition>: checks it and mounts it writable. Sets
# BESIDE_MNT, BESIDE_DIR (the Android directory) and BESIDE_FSMOD (GRUB
# filesystem module).
beside_open() {
    local name fstype
    name=$(si_install_name)
    source_find || si_die "$SRC_MSG"
    probe_sizes
    fstype=$(si_blkid "$1" TYPE)
    case $fstype in
    ext4) BESIDE_FSMOD=ext2 ;;
    f2fs) BESIDE_FSMOD=f2fs ;;
    ntfs) BESIDE_FSMOD=ntfs ;;
    *) si_die "Only EXT4, F2FS and NTFS are supported" ;;
    esac
    if [ "$1" = "$SRC_DIR_DEV" ] && [ "$SRC_DIR_NAME" = "$name" ]; then
        si_die "This is the running system"
    fi
    si_mount "$1" rw || si_die "Could not mount $1"
    BESIDE_MNT=$SI_MNT
    if ! touch "$BESIDE_MNT/.systeminstaller" 2>/dev/null; then
        si_die "$1 can only be mounted read-only. If it is used by Windows, turn off Fast Startup and shut Windows down completely."
    fi
    rm -f "$BESIDE_MNT/.systeminstaller"
    BESIDE_DIR=$BESIDE_MNT/$name
    if [ "$FIRMWARE" = linux ]; then
        beside_linux_firmware "$BESIDE_MNT" || si_die "$1 has no firmware directory of a Linux system"
        MIB_BESIDE=$((MIB_BESIDE - MIB_firmware))
    fi
}

# beside_install <partition>
beside_install() {
    local need
    beside_open "$1"
    [ -e "$BESIDE_DIR" ] && si_die "There is already an installation on $1"
    # Directories need a filesystem with Linux permissions
    [ "$BESIDE_FSMOD" = ntfs ] && MOUNT_USERDATA=imgs
    need=$((MIB_BESIDE + $(install_userdata_mib "$MOUNT_USERDATA" 1024)))
    [ "$(si_free "$BESIDE_MNT")" -ge "$need" ] || si_die "At least $need MiB of free space are needed"

    si_stage destructive
    mkdir -p "$BESIDE_DIR"
    beside_write "$1" 1
}

# beside_upgrade <partition>
beside_upgrade() {
    local need
    beside_open "$1"
    [ -f "$BESIDE_DIR/system.img" ] || si_die "No installation on $1"
    # Installed with the firmware of the Linux system
    if [ ! -f "$BESIDE_DIR/firmware.img" ] && beside_linux_firmware "$BESIDE_MNT"; then
        FIRMWARE=linux
        MIB_firmware=0
    fi
    install_check_downgrade "$(si_build_date "$BESIDE_DIR/system.img")"
    MOUNT_USERDATA=bind_mount_dir
    [ -f "$BESIDE_DIR/userdata.img" ] && MOUNT_USERDATA=imgs
    need=$(install_upgrade_mib)
    [ "$(si_free "$BESIDE_MNT")" -ge "$need" ] || si_die "At least $need MiB of free space are needed"

    si_stage destructive
    beside_write "$1" 0
}

# beside_write <partition> <new installation: 1|0>
beside_write() {
    local cmdline
    install_system "$BESIDE_DIR" 2 80
    install_boot_files "$BESIDE_DIR" 83
    [ "$2" = 1 ] && install_userdata_files "$BESIDE_DIR" 92
    sync

    cmdline="$CMDLINE androidboot.android_dir=$(si_install_name) androidboot.mount_system=imgs"
    if [ "$FIRMWARE" = linux ]; then
        cmdline="$cmdline androidboot.mount_firmware=all_possible_dirs"
    elif [ "$INSTALL_FIRMWARE" = 1 ]; then
        cmdline="$cmdline androidboot.mount_firmware=img"
    else
        cmdline="$cmdline androidboot.mount_firmware=false"
    fi
    if [ "$BOOT_ENTRIES" = 1 ]; then
        si_progress 95 "Adding boot entries"
        beside_entries "$1" "$BESIDE_MNT" "$(si_title)" "$cmdline" "$MOUNT_USERDATA" "$BESIDE_FSMOD"
    fi
    si_save_log "$BESIDE_DIR"
    sync
    si_umount "$BESIDE_MNT"
    si_progress 100 "Done"
}
