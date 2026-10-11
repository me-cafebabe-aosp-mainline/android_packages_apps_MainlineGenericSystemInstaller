#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Installations and upgrades.
#

# install_check_downgrade <build date of the installation> <allowed: 1|0>
install_check_downgrade() {
    local running
    running=$(getprop ro.build.date.utc)
    if [ -n "$1" ] && [ "$1" -gt "$running" ] && [ "$2" != 1 ]; then
        si_die "The installed system is newer than this one. Android can not use user data of a newer build."
    fi
}

# install_grub_efi <directory> <fallback|named>: copies the GRUB EFI images,
# as the fallback boot loaders (\EFI\BOOT\BOOTX64.EFI and so on), or with a
# name of their own for the firmware of this machine
install_grub_efi() {
    local f
    if [ "$2" = fallback ]; then
        for f in x86_64-efi:BOOTX64.EFI i386-efi:BOOTIA32.EFI arm64-efi:BOOTAA64.EFI; do
            [ -f "$SI_GRUB/${f%%:*}.efi" ] && cp "$SI_GRUB/${f%%:*}.efi" "$1/${f#*:}"
        done
    else
        case $(uname -m):$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null) in
        x86_64:32) cp "$SI_GRUB/i386-efi.efi" "$1/grubia32.efi" ;;
        x86_64:*) cp "$SI_GRUB/x86_64-efi.efi" "$1/grubx64.efi" ;;
        aarch64:*) cp "$SI_GRUB/arm64-efi.efi" "$1/grubaa64.efi" ;;
        esac
    fi
    cp "$SI_GRUB/unicode.pf2" "$1/"
}

# install_disk <disk> <kernel command line> <upgrade: 1|0> <allow downgrade: 1|0>
# SIZE_<partition> (MiB) overrides the default size of a partition,
# USERDATA_FS (ext4 or f2fs) is the filesystem of userdata
install_disk() {
    local disk dev bios p src part mib sizes total done_mib from esp firmware need size min
    disk=$1
    dev=/dev/block/$disk
    [ -b "$dev" ] || si_die "No disk $disk"
    source_find || si_die "$SRC_MSG"
    probe_sizes
    source_disks | grep -qx "$disk" && si_die "The running system is on this disk"
    si_busy_disks | grep -qx "$disk" && si_die "A partition of this disk is in use"

    bios=0
    [ -f "$SI_GRUB/i386-pc-core.img" ] && bios=1

    if [ "$3" = 1 ]; then
        for p in $(si_partitions "$disk"); do
            case $(si_partname "$p") in
            bios | efi | system | system_dlkm | vendor | vendor_dlkm | metadata | userdata)
                eval "PART_$(si_partname "$p")=\$p"
                ;;
            esp) PART_efi=$p ;;
            esac
        done
        [ -n "$PART_efi" ] && [ -n "$PART_system" ] && [ -n "$PART_userdata" ] ||
            si_die "No installation on $disk"
        install_check_downgrade "$(si_build_date "/dev/block/$PART_system")" "$4"
        for p in $LAYOUT_SYSTEM_PARTS; do
            eval "src=\$SRC_$p part=\$PART_$p mib=\$MIB_$p"
            [ -n "$src" ] || continue
            [ -n "$part" ] || si_die "The installation has no $p partition"
            [ "$mib" -le "$(si_mib "$(si_size "$part")")" ] || si_die "The $p partition is too small"
        done
        [ -n "$PART_bios" ] || bios=0
    else
        sizes=
        need=$((2 + LAYOUT_MIN_USERDATA))
        [ "$bios" = 1 ] && need=$((need + LAYOUT_SIZE_bios))
        for p in efi $LAYOUT_SYSTEM_PARTS metadata; do
            if [ "$p" = metadata ]; then
                mib=0
                size=$LAYOUT_SIZE_metadata
            else
                eval "mib=\$MIB_$p"
                size=$(layout_size "$p" "$mib")
            fi
            eval "size=\${SIZE_$p:-$size}"
            min=$(layout_minimum "$p" "$mib")
            [ "$size" -ge "$min" ] 2>/dev/null || si_die "The $p partition needs at least $min MiB"
            sizes="$sizes $size"
            need=$((need + size))
        done
        [ "$(si_mib "$(si_size "$disk")")" -ge "$need" ] || si_die "At least $need MiB are needed"
        blockdev --rereadpt "$dev" || si_die "The disk is in use"
    fi

    si_stage destructive
    if [ "$3" != 1 ]; then
        si_progress 1 "Partitioning"
        layout_create sgdisk "$dev" "$bios" $sizes 0 ||
            si_die "Could not partition the disk"
        blockdev --rereadpt "$dev"
        for p in $(layout_parts "$bios"); do
            part=$(si_part_dev "$disk" "$(layout_number "$bios" "$p")")
            si_wait_dev "$part" || si_die "The new partitions did not appear"
            eval "PART_$p=\$part"
        done
    fi

    total=0
    for p in $LAYOUT_SYSTEM_PARTS; do
        eval "mib=\$MIB_$p"
        total=$((total + mib))
    done
    done_mib=0
    for p in $LAYOUT_SYSTEM_PARTS; do
        eval "src=\$SRC_$p part=\$PART_$p mib=\$MIB_$p"
        [ -n "$src" ] || continue
        from=$((5 + 70 * done_mib / total))
        done_mib=$((done_mib + mib))
        si_copy "/dev/block/$src" "/dev/block/$part" "$mib" "$from" $((5 + 70 * done_mib / total)) "Copying $p"
    done

    if [ "$3" != 1 ]; then
        si_progress 76 "Formatting metadata as EXT4 and userdata as $(echo "${USERDATA_FS:-ext4}" | tr a-z A-Z)"
        si_mkfs_userdata "/dev/block/$PART_metadata" ext4 metadata ||
            si_die "Could not format the metadata partition"
        si_mkfs_userdata "/dev/block/$PART_userdata" "${USERDATA_FS:-ext4}" userdata ||
            si_die "Could not format the userdata partition"
        si_progress 80 "Formatting the EFI system partition as FAT32"
        newfs_msdos -F 32 -L ESP "/dev/block/$PART_efi" >/dev/null ||
            si_die "Could not format the EFI system partition"
    fi

    if [ "$bios" = 1 ]; then
        si_progress 81 "Installing the BIOS boot code"
        bootcode_install "$dev" "$SI_GRUB/i386-pc-boot.img" "$SI_GRUB/i386-pc-core.img" \
            "$(layout_first_sector sgdisk "$dev" "$(cat "/sys/class/block/$PART_bios/partition")")" ||
            si_die "Could not install the BIOS boot code"
    fi

    si_progress 82 "Copying the kernel"
    si_mount "$PART_efi" rw || si_die "Could not mount the EFI system partition"
    esp=$SI_MNT
    mkdir -p "$esp/EFI/BOOT" "$esp/android"
    install_grub_efi "$esp/EFI/BOOT" fallback || si_die "Could not copy GRUB"
    cp "$SRC_DIR/kernel" "$SRC_DIR/ramdisk-all-combined.img" "$esp/android/" ||
        si_die "Could not copy the kernel"
    si_progress 88 "Copying the firmware"
    rm -f "$esp/android/firmware.img"
    if source_write_firmware "$esp/android/firmware.img"; then
        firmware=1
    else
        rm -f "$esp/android/firmware.img"
        firmware=0
    fi
    grubcfg_disk "$(si_title)" "$(si_blkid "$PART_efi" UUID)" "$2" "$firmware" >"$esp/EFI/BOOT/grub.cfg"
    si_save_log "$esp/android"
    sync
    si_umount "$esp"

    sync
    si_progress 100 "Done"
}

# install_find_esp <disk>: the EFI system partition of a disk
install_find_esp() {
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

# install_linux_dev <directory>: fills it like /dev of a Linux system:
# block devices as /dev/<name> and /dev/disk/by-*, not /dev/block/<name>
# like Android, which grub-mkconfig would write to the menu entries
install_linux_dev() {
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

# install_update_grub <partition> <root of a Linux system on it>:
# regenerates its grub.cfg
#
# grub-mkconfig finds the root device in /proc/self/mountinfo, where it is
# the device the partition was mounted from: it is mounted again from
# /dev/<name> for that, and the chroot gets a /dev of a Linux system.
install_update_grub() {
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
    install_linux_dev "$dev"

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

# install_linux_grub <partition> <root of a Linux system on it> <title>
# <menu entries>: adds the entries to its GRUB menu
install_linux_grub() {
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
    if install_update_grub "$part" "$r"; then
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

# install_beside_entries <partition> <mount point> <title> <kernel command
# line> <userdata mount method> <GRUB filesystem module>
install_beside_entries() {
    local name entries added esp d
    name=$(si_install_name)
    entries=$(grubcfg_entries "$3" "$(si_blkid "$1" UUID)" "$6" "$name" "$4" "$5")
    added=0

    if [ -d /sys/firmware/efi ] && esp=$(install_find_esp "$(si_disk_of "$1")") &&
        si_mount "$esp" rw; then
        d=$SI_MNT/EFI/$name
        mkdir -p "$d"
        install_grub_efi "$d" named
        {
            grubcfg_header
            printf '%s\n' "$entries"
        } >"$d/grub.cfg"
        sync
        echo "Added GRUB as \\EFI\\$name on the EFI system partition: choose it in the boot menu of the firmware"
        si_umount "$SI_MNT"
        added=1
    fi

    if [ -d "$2/etc/grub.d" ] && install_linux_grub "$1" "$2" "$3" "$entries"; then
        added=1
    fi

    [ "$added" = 1 ] || echo "No boot entry was added: add one by hand"
}

# install_beside <partition> <userdata MiB> <kernel command line>
# <boot entries: 1|0> <upgrade: 1|0> <allow downgrade: 1|0>
# USERDATA_FS (ext4 or f2fs) is the filesystem of userdata.img on NTFS
install_beside() {
    local part name fstype m dir mode need total p mib done_mib src from f cmdline
    part=$1
    name=$(si_install_name)
    source_find || si_die "$SRC_MSG"
    probe_sizes

    fstype=$(si_blkid "$part" TYPE)
    case $fstype in
    ext4) fsmod=ext2 ;;
    f2fs) fsmod=f2fs ;;
    ntfs) fsmod=ntfs ;;
    *) si_die "Only EXT4, F2FS and NTFS are supported" ;;
    esac
    if [ "$part" = "$SRC_DIR_DEV" ] && [ "$SRC_DIR_NAME" = "$name" ]; then
        si_die "This is the running system"
    fi
    si_mount "$part" rw || si_die "Could not mount $part"
    m=$SI_MNT
    if ! touch "$m/.systeminstaller" 2>/dev/null; then
        si_die "$part can only be mounted read-only. If it is used by Windows, turn off Fast Startup and shut Windows down completely."
    fi
    rm -f "$m/.systeminstaller"

    dir=$m/$name
    if [ "$5" = 1 ]; then
        [ -f "$dir/system.img" ] || si_die "No installation on $part"
        install_check_downgrade "$(si_build_date "$dir/system.img")" "$6"
        if [ -f "$dir/userdata.img" ]; then
            mode=imgs
        else
            mode=bind_mount_dir
        fi
        need=$MIB_BESIDE
    else
        [ -e "$dir" ] && si_die "There is already an installation on $part"
        if [ "$fstype" = ntfs ]; then
            mode=imgs
            need=$((MIB_BESIDE + $2 + LAYOUT_SIZE_metadata))
        else
            mode=bind_mount_dir
            need=$((MIB_BESIDE + 1024))
        fi
    fi
    [ "$(si_free "$m")" -ge "$need" ] || si_die "At least $need MiB of free space are needed"

    si_stage destructive
    mkdir -p "$dir"
    total=0
    for p in $LAYOUT_SYSTEM_PARTS; do
        eval "mib=\$MIB_$p"
        total=$((total + mib))
    done
    done_mib=0
    for p in $LAYOUT_SYSTEM_PARTS; do
        eval "src=\$SRC_$p mib=\$MIB_$p"
        [ -n "$src" ] || continue
        from=$((2 + 80 * done_mib / total))
        done_mib=$((done_mib + mib))
        rm -f "$dir/$p.img.new"
        si_copy "/dev/block/$src" "$dir/$p.img.new" "$mib" "$from" $((2 + 80 * done_mib / total)) "Copying $p"
        mv -f "$dir/$p.img.new" "$dir/$p.img"
    done

    si_progress 83 "Copying the kernel"
    for f in kernel ramdisk-all-combined.img; do
        cp "$SRC_DIR/$f" "$dir/$f.new" && mv -f "$dir/$f.new" "$dir/$f" || si_die "Could not copy $f"
    done
    si_progress 87 "Copying the firmware"
    rm -f "$dir/firmware.img.new"
    if source_write_firmware "$dir/firmware.img.new"; then
        mv -f "$dir/firmware.img.new" "$dir/firmware.img"
    else
        rm -f "$dir/firmware.img.new"
    fi

    if [ "$5" != 1 ]; then
        if [ "$mode" = imgs ]; then
            si_progress 92 "Creating userdata.img as $(echo "${USERDATA_FS:-ext4}" | tr a-z A-Z)"
            truncate -s "${2}M" "$dir/userdata.img" &&
                si_mkfs_userdata "$dir/userdata.img" "${USERDATA_FS:-ext4}" ||
                si_die "Could not create userdata.img"
            truncate -s "${LAYOUT_SIZE_metadata}M" "$dir/metadata.img" &&
                si_mkfs_userdata "$dir/metadata.img" ext4 ||
                si_die "Could not create metadata.img"
        else
            si_progress 92 "Creating the user data directories"
            mkdir -m 0771 "$dir/userdata" "$dir/metadata" || si_die "Could not create the user data"
        fi
    fi
    sync

    cmdline="$3 androidboot.android_dir=$name androidboot.mount_system=imgs"
    [ -f "$dir/firmware.img" ] && cmdline="$cmdline androidboot.mount_firmware=img"
    if [ "$4" = 1 ]; then
        si_progress 95 "Adding boot entries"
        install_beside_entries "$part" "$m" "$(si_title)" "$cmdline" "$mode" "$fsmod"
    fi
    si_save_log "$dir"
    sync
    si_umount "$m"
    si_progress 100 "Done"
}
