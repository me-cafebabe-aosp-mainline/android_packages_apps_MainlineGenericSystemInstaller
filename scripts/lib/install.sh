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
install_disk() {
    local disk dev bios p src part mib sizes total done_mib from esp firmware
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
            bios | esp | system | system_dlkm | vendor | vendor_dlkm | metadata | userdata)
                eval "PART_$(si_partname "$p")=\$p"
                ;;
            esac
        done
        [ -n "$PART_esp" ] && [ -n "$PART_system" ] && [ -n "$PART_userdata" ] ||
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
        [ "$(si_mib "$(si_size "$disk")")" -ge "$MIB_DISK" ] || si_die "At least $MIB_DISK MiB are needed"
        blockdev --rereadpt "$dev" || si_die "The disk is in use"
    fi

    si_stage destructive
    if [ "$3" != 1 ]; then
        si_progress 1 "Partitioning"
        sizes=$(layout_size esp $((MIB_kernel + MIB_ramdisk + MIB_firmware + 16)))
        for p in $LAYOUT_SYSTEM_PARTS; do
            eval "mib=\$MIB_$p"
            sizes="$sizes $(layout_size "$p" "$mib")"
        done
        layout_create sgdisk "$dev" "$bios" $sizes "$LAYOUT_SIZE_metadata" 0 ||
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
        si_progress 76 "Formatting the user data partitions"
        # Android should format empty partitions on the first boot, but
        # does not yet.
        mke2fs -q -F -t ext4 -b 4096 -L metadata "/dev/block/$PART_metadata" ||
            si_die "Could not format the metadata partition"
        mke2fs -q -F -t ext4 -b 4096 -L userdata "/dev/block/$PART_userdata" ||
            si_die "Could not format the userdata partition"
        si_progress 80 "Formatting the EFI system partition"
        newfs_msdos -F 32 -L ESP "/dev/block/$PART_esp" >/dev/null ||
            si_die "Could not format the EFI system partition"
    fi

    si_progress 82 "Copying the kernel"
    si_mount "$PART_esp" rw || si_die "Could not mount the EFI system partition"
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
    grubcfg_disk "$(si_title)" "$(si_blkid "$PART_esp" UUID)" "$2" "$firmware" >"$esp/EFI/BOOT/grub.cfg"
    sync
    si_umount "$esp"

    if [ "$bios" = 1 ]; then
        si_progress 97 "Installing the BIOS boot code"
        bootcode_install "$dev" "$SI_GRUB/i386-pc-boot.img" "$SI_GRUB/i386-pc-core.img" \
            "$(layout_first_sector sgdisk "$dev" "$(cat "/sys/class/block/$PART_bios/partition")")" ||
            si_die "Could not install the BIOS boot code"
    fi
    sync
    si_progress 100 "Done"
}

# install_find_esp <disk>: the EFI system partition of a disk
install_find_esp() {
    local p n
    for p in $(si_partitions "$1"); do
        n=$(cat "/sys/class/block/$p/partition")
        if sgdisk -i "$n" "/dev/block/$1" 2>/dev/null | grep -qi 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B'; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

# install_update_grub <root of a Linux system>: regenerates its grub.cfg
install_update_grub() {
    local r bound n rc t b
    r=$1
    if [ -x "$r/usr/sbin/update-grub" ]; then
        set -- /usr/sbin/update-grub
    elif [ -x "$r/usr/sbin/grub2-mkconfig" ] && [ -f "$r/boot/grub2/grub.cfg" ]; then
        set -- /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
    elif [ -x "$r/usr/sbin/grub-mkconfig" ] && [ -f "$r/boot/grub/grub.cfg" ]; then
        set -- /usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg
    else
        return 1
    fi
    bound=
    n=0
    rc=1
    for t in dev proc sys; do
        mount --bind "/$t" "$r/$t" || break
        bound="$r/$t $bound"
        n=$((n + 1))
    done
    if [ "$n" = 3 ]; then
        PATH=/usr/sbin:/usr/bin:/sbin:/bin chroot "$r" "$@" && rc=0
    fi
    for b in $bound; do
        umount "$b" || umount -l "$b"
    done
    return $rc
}

# install_linux_grub <root of a Linux system> <title> <menu entries>: adds
# the entries to its GRUB menu
install_linux_grub() {
    local r name script cfgdir d begin end
    r=$1
    name=$(si_install_name)
    script=$r/etc/grub.d/35_$name
    {
        printf '#!/bin/sh\n# Added by the installer of %s\n' "$2"
        echo "cat <<'EOF'"
        printf '%s\n' "$3"
        echo EOF
    } >"$script"
    chmod 0755 "$script"
    if install_update_grub "$r"; then
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

    if [ -d "$2/etc/grub.d" ] && install_linux_grub "$2" "$3" "$entries"; then
        added=1
    fi

    [ "$added" = 1 ] || echo "No boot entry was added: add one by hand"
}

# install_beside <partition> <userdata MiB> <kernel command line>
# <boot entries: 1|0> <upgrade: 1|0> <allow downgrade: 1|0>
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
    *) si_die "Only ext4, F2FS and NTFS are supported" ;;
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
        si_progress 92 "Creating the user data"
        if [ "$mode" = imgs ]; then
            # Android should format empty images on the first boot, but
            # does not yet.
            for f in userdata:$2 metadata:$LAYOUT_SIZE_metadata; do
                truncate -s "${f#*:}M" "$dir/${f%%:*}.img" &&
                    mke2fs -q -F -t ext4 -b 4096 "$dir/${f%%:*}.img" ||
                    si_die "Could not create ${f%%:*}.img"
            done
        else
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
    si_umount "$m"
    si_progress 100 "Done"
}
