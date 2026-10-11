#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# What both kinds of installation write: the system (to partitions or to
# images), and the Android directory (kernel, ramdisk, firmware image, user
# data images or directories). Whole disk: disk.sh, beside another
# operating system: beside.sh. The options (MOUNT_*, USERDATA_*...) are
# described in systeminstaller.sh.
#

# install_check_downgrade <build date of the installation>
install_check_downgrade() {
    local running
    running=$(getprop ro.build.date.utc)
    if [ -n "$1" ] && [ "$1" -gt "$running" ] && [ "$ALLOW_DOWNGRADE" != 1 ]; then
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

# install_system_mib: MiB of the system, all partitions
install_system_mib() {
    local p mib total
    total=0
    for p in $LAYOUT_SYSTEM_PARTS; do
        eval "mib=\$MIB_$p"
        total=$((total + mib))
    done
    echo "$total"
}

# install_upgrade_mib: free MiB an upgrade of images needs. Files are
# replaced one by one: room for the biggest one.
install_upgrade_mib() {
    local p mib need
    need=$MIB_firmware
    for p in $LAYOUT_SYSTEM_PARTS; do
        eval "mib=\$MIB_$p"
        [ "$mib" -gt "$need" ] && need=$mib
    done
    echo $((need + 64))
}

# install_system <partitions|directory> <from percent> <to percent>: copies
# the system to the partitions PART_<partition>, or as images to a
# directory, each image replaced once complete
install_system() {
    local total done_mib p src mib from to dst
    total=$(install_system_mib)
    done_mib=0
    for p in $LAYOUT_SYSTEM_PARTS; do
        eval "src=\$SRC_$p mib=\$MIB_$p"
        [ -n "$src" ] || continue
        from=$(($2 + ($3 - $2) * done_mib / total))
        done_mib=$((done_mib + mib))
        to=$(($2 + ($3 - $2) * done_mib / total))
        if [ "$1" = partitions ]; then
            eval "dst=/dev/block/\$PART_$p"
            # Rewritten whole: also what the image does not cover
            si_discard "$dst"
            si_copy "/dev/block/$src" "$dst" "$mib" "$from" "$to" "Copying $p"
        else
            rm -f "$1/$p.img.new"
            si_copy "/dev/block/$src" "$1/$p.img.new" "$mib" "$from" "$to" "Copying $p"
            mv -f "$1/$p.img.new" "$1/$p.img"
        fi
    done
}

# install_boot_files <Android directory> <percent>: kernel, ramdisk and
# firmware image, none with FIRMWARE=linux. Sets INSTALL_FIRMWARE to 1 if
# there is a firmware image.
install_boot_files() {
    local f
    si_progress "$2" "Copying the kernel"
    for f in kernel ramdisk-all-combined.img; do
        cp "$SRC_DIR/$f" "$1/$f.new" && mv -f "$1/$f.new" "$1/$f" || si_die "Could not copy $f"
    done
    rm -f "$1/firmware.img.new"
    if [ "$FIRMWARE" = linux ]; then
        rm -f "$1/firmware.img"
    else
        si_progress $(($2 + 5)) "Copying the firmware"
        if source_write_firmware "$1/firmware.img.new"; then
            mv -f "$1/firmware.img.new" "$1/firmware.img"
        else
            rm -f "$1/firmware.img.new"
        fi
    fi
    INSTALL_FIRMWARE=0
    [ -f "$1/firmware.img" ] && INSTALL_FIRMWARE=1
}

# install_userdata_mib <imgs|bind_mount_dir> <MiB for directories>: room
# for the user data of a new installation in the Android directory
install_userdata_mib() {
    case $1 in
    imgs) echo $((USERDATA_SIZE + LAYOUT_SIZE_metadata)) ;;
    *) echo "$2" ;;
    esac
}

# install_userdata_files <Android directory> <percent>: user data of a new
# installation, as MOUNT_USERDATA says, and the directories of
# MOUNT_OVERLAY=dirs
install_userdata_files() {
    local p
    case $MOUNT_USERDATA in
    imgs)
        si_progress "$2" "Creating userdata.img as $(si_upper "$USERDATA_FS")"
        truncate -s "${USERDATA_SIZE}M" "$1/userdata.img" &&
            si_mkfs_userdata "$1/userdata.img" "$USERDATA_FS" ||
            si_die "Could not create userdata.img"
        truncate -s "${LAYOUT_SIZE_metadata}M" "$1/metadata.img" &&
            si_mkfs_userdata "$1/metadata.img" ext4 ||
            si_die "Could not create metadata.img"
        ;;
    bind_mount_dir)
        si_progress "$2" "Creating the user data directories"
        mkdir -m 0771 "$1/userdata" "$1/metadata" || si_die "Could not create the user data"
        ;;
    esac
    # The root of an overlay gives its mode and owner to the root of the
    # partition
    if [ "$MOUNT_OVERLAY" = dirs ]; then
        for p in $LAYOUT_OVERLAY_PARTS; do
            mkdir -m 0755 "$1/${p}_overlay" || si_die "Could not create ${p}_overlay"
        done
    fi
}
