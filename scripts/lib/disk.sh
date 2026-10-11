#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Whole disk installations: the partitions of layout.sh, the GRUB boot
# code and boot loaders, the system and the Android directory.
#
# With images or directories for the system or the user data, an android
# partition holds the Android directory, with the kernel; the EFI system
# partition only holds GRUB. Otherwise the Android directory is on the EFI
# system partition, where only overlay images can be added (overlayfs
# refuses FAT32 directories).
#
# disk_install uses the options of systeminstaller.sh, disk_upgrade reads
# them from the installation.
#

# disk_check <disk>: what gets installed is found, and the disk is not used.
# Sets DISK_BIOS to 1 to install the BIOS boot code.
disk_check() {
    [ -b "/dev/block/$1" ] || si_die "No disk $1"
    source_find || si_die "$SRC_MSG"
    probe_sizes
    source_disks | grep -qx "$1" && si_die "The running system is on this disk"
    si_busy_disks | grep -qx "$1" && si_die "A partition of this disk is in use"
    DISK_BIOS=0
    [ -f "$SI_GRUB/i386-pc-core.img" ] && DISK_BIOS=1
}

# disk_param <grub.cfg> <name>: value of androidboot.<name> in its first entry
disk_param() {
    sed -n "s/.*androidboot\.$2=\([a-z_]*\).*/\1/p" "$1" 2>/dev/null | head -n 1
}

#
# Upgrades
#

# disk_find <disk>: PART_<name> of the installation on it, and the MOUNT_*
# it was installed with
disk_find() {
    local p cfg
    for p in $(si_partitions "$1"); do
        case $(si_partname "$p") in
        bios | efi | system | system_dlkm | vendor | vendor_dlkm | metadata | userdata | android | \
            system_overlay | vendor_overlay)
            eval "PART_$(si_partname "$p")=\$p"
            ;;
        esp) PART_efi=$p ;;
        esac
    done
    [ -n "$PART_efi" ] || si_die "No installation on $1"
    si_mount "$PART_efi" || si_die "Could not mount the EFI system partition"
    cfg=$SI_MNT/EFI/BOOT/grub.cfg
    MOUNT_SYSTEM=$(disk_param "$cfg" mount_system)
    MOUNT_USERDATA=$(disk_param "$cfg" mount_userdata)
    MOUNT_OVERLAY=$(disk_param "$cfg" mount_overlay)
    si_umount "$SI_MNT"
    [ -n "$PART_system" ] && MOUNT_SYSTEM=std_parts
    [ -n "$PART_userdata" ] && MOUNT_USERDATA=std_parts
    for p in $LAYOUT_OVERLAY_PARTS; do
        eval "[ -n \"\$PART_${p}_overlay\" ]" && MOUNT_OVERLAY=${MOUNT_OVERLAY:-std_parts}
    done
    [ -n "$MOUNT_SYSTEM" ] && [ -n "$MOUNT_USERDATA" ] || si_die "No installation on $1"
    if [ "$MOUNT_SYSTEM" != std_parts ] || [ "$MOUNT_USERDATA" != std_parts ]; then
        [ -n "$PART_android" ] || si_die "No installation on $1"
    fi
}

# disk_upgrade <disk>
disk_upgrade() {
    local p src part mib need
    disk_check "$1"
    disk_find "$1"
    if [ "$MOUNT_SYSTEM" = std_parts ]; then
        install_check_downgrade "$(si_build_date "/dev/block/$PART_system")"
        for p in $LAYOUT_SYSTEM_PARTS; do
            eval "src=\$SRC_$p part=\$PART_$p mib=\$MIB_$p"
            [ -n "$src" ] || continue
            [ -n "$part" ] || si_die "The installation has no $p partition"
            [ "$mib" -le "$(si_mib "$(si_size "$part")")" ] || si_die "The $p partition is too small"
        done
    else
        si_mount "$PART_android" || si_die "Could not mount the android partition"
        [ -f "$SI_MNT/android/system.img" ] || si_die "No installation on $1"
        install_check_downgrade "$(si_build_date "$SI_MNT/android/system.img")"
        need=$(install_upgrade_mib)
        [ "$(si_free "$SI_MNT")" -ge "$need" ] ||
            si_die "At least $need MiB of free space are needed on the android partition"
        si_umount "$SI_MNT"
    fi
    [ -n "$PART_bios" ] || DISK_BIOS=0

    si_stage destructive
    disk_write "$1" 0
}

#
# New installations
#

# disk_plan <disk>: sets the LAYOUT_* of the options, and DISK_SIZES, the
# sizes in MiB of the partitions after bios but the last one, which takes
# the rest. Checks that everything fits.
disk_plan() {
    local p mib size min last need
    LAYOUT_SYSTEM=0
    [ "$MOUNT_SYSTEM" = std_parts ] && LAYOUT_SYSTEM=1
    LAYOUT_USERDATA=0
    [ "$MOUNT_USERDATA" = std_parts ] && LAYOUT_USERDATA=1
    LAYOUT_ANDROID=0
    [ "$LAYOUT_SYSTEM" = 1 ] && [ "$LAYOUT_USERDATA" = 1 ] || LAYOUT_ANDROID=1

    # Overlay partitions: those given a size
    LAYOUT_OVERLAYS=
    if [ "$MOUNT_OVERLAY" = std_parts ]; then
        for p in $LAYOUT_OVERLAY_PARTS; do
            eval "size=\${SIZE_${p}_overlay:-0}"
            [ "$size" -gt 0 ] 2>/dev/null && LAYOUT_OVERLAYS="$LAYOUT_OVERLAYS $p"
        done
        [ -n "$LAYOUT_OVERLAYS" ] || si_die "No overlay partition was given a size"
    fi
    if [ "$MOUNT_OVERLAY" = dirs ] && [ "$LAYOUT_ANDROID" = 0 ]; then
        si_die "Overlay directories need an android partition: images or directories for the system or the user data"
    fi

    DISK_SIZES=
    need=2
    [ "$DISK_BIOS" = 1 ] && need=$((need + LAYOUT_SIZE_bios))
    last=$(layout_parts "$DISK_BIOS" | awk '{ print $NF }')
    for p in $(layout_parts "$DISK_BIOS"); do
        case $p in
        bios | "$last") continue ;;
        efi)
            # Only GRUB with an android partition
            mib=$MIB_efi
            [ "$LAYOUT_ANDROID" = 1 ] && mib=16
            size=$(layout_size efi "$mib")
            ;;
        metadata)
            mib=0
            size=$LAYOUT_SIZE_metadata
            ;;
        *_overlay)
            mib=0
            size=0
            ;;
        android)
            # Before metadata and userdata: the system images and the kernel
            mib=$MIB_BESIDE
            size=$(layout_size android "$mib")
            ;;
        *)
            eval "mib=\$MIB_$p"
            size=$(layout_size "$p" "$mib")
            ;;
        esac
        eval "size=\${SIZE_$p:-$size}"
        min=$(layout_minimum "$p" "$mib")
        [ "$size" -ge "$min" ] 2>/dev/null || si_die "The $p partition needs at least $min MiB"
        DISK_SIZES="$DISK_SIZES $size"
        need=$((need + size))
    done
    if [ "$last" = userdata ]; then
        need=$((need + LAYOUT_MIN_USERDATA))
    else
        # The android partition: the kernel, the system images, the user data
        need=$((need + MIB_BESIDE + $(install_userdata_mib "$MOUNT_USERDATA" "$LAYOUT_MIN_USERDATA")))
        [ "$LAYOUT_SYSTEM" = 1 ] && need=$((need - $(install_system_mib)))
    fi
    [ "$(si_mib "$(si_size "$1")")" -ge "$need" ] || si_die "At least $need MiB are needed"
}

# disk_create <disk>: partitions and filesystems
disk_create() {
    local dev p part clusters out
    dev=/dev/block/$1
    si_progress 1 "Discarding the disk"
    si_discard "$dev"
    si_progress 1 "Partitioning"
    layout_create sgdisk "$dev" "$DISK_BIOS" $DISK_SIZES 0 || si_die "Could not partition the disk"
    blockdev --rereadpt "$dev"
    for p in $(layout_parts "$DISK_BIOS"); do
        part=$(si_part_dev "$1" "$(layout_number "$DISK_BIOS" "$p")")
        si_wait_dev "$part" || si_die "The new partitions did not appear"
        eval "PART_$p=\$part"
    done

    si_progress 2 "Formatting"
    if [ "$LAYOUT_USERDATA" = 1 ]; then
        si_mkfs_userdata "/dev/block/$PART_metadata" ext4 metadata ||
            si_die "Could not format the metadata partition"
        si_mkfs_userdata "/dev/block/$PART_userdata" "$USERDATA_FS" userdata ||
            si_die "Could not format the userdata partition"
    fi
    if [ "$LAYOUT_ANDROID" = 1 ]; then
        si_mkfs "/dev/block/$PART_android" "$ANDROID_FS" android ||
            si_die "Could not format the android partition"
    fi
    for p in $(layout_overlays); do
        eval "part=\$PART_$p"
        si_mkfs "/dev/block/$part" ext4 "$p" || si_die "Could not format the $p partition"
        # Its root is laid over the one of the partition: nothing in it
        if si_mount "$part" rw; then
            rmdir "${SI_MNT:?}/lost+found"
            si_umount "$SI_MNT"
        fi
    done
    # FAT32 needs at least 65525 clusters: newfs_msdos picks too big ones
    # for some sizes (16 KiB for 1 GiB). 4 KiB, or 512 bytes below 300 MiB.
    clusters=8
    [ "$(si_mib "$(si_size "$PART_efi")")" -ge 300 ] || clusters=1
    # Its output only on failure: it always warns about a block device
    out=$(newfs_msdos -F 32 -c "$clusters" -L ESP "/dev/block/$PART_efi" 2>&1) ||
        si_die "Could not format the EFI system partition: $out"
}

# disk_install <disk>
disk_install() {
    disk_check "$1"
    disk_plan "$1"
    blockdev --rereadpt "/dev/block/$1" || si_die "The disk is in use"

    si_stage destructive
    disk_create "$1"
    disk_write "$1" 1
}

#
# Both
#

# disk_write <disk> <new installation: 1|0>: the system, the boot code, the
# Android directory and the boot entries
disk_write() {
    local esp m dir part fsmod
    [ "$MOUNT_SYSTEM" = std_parts ] && install_system partitions 5 75

    if [ "$DISK_BIOS" = 1 ]; then
        si_progress 76 "Installing the BIOS boot code"
        bootcode_install "/dev/block/$1" "$SI_GRUB/i386-pc-boot.img" "$SI_GRUB/i386-pc-core.img" \
            "$(layout_first_sector sgdisk "/dev/block/$1" "$(cat "/sys/class/block/$PART_bios/partition")")" ||
            si_die "Could not install the BIOS boot code"
    fi

    si_mount "$PART_efi" rw || si_die "Could not mount the EFI system partition"
    esp=$SI_MNT
    mkdir -p "$esp/EFI/BOOT"
    install_grub_efi "$esp/EFI/BOOT" fallback || si_die "Could not copy GRUB"
    if [ -n "$PART_android" ]; then
        si_mount "$PART_android" rw || si_die "Could not mount the android partition"
        m=$SI_MNT
        part=$PART_android
        fsmod=ext2
        [ "$SI_FSTYPE" = f2fs ] && fsmod=f2fs
    else
        m=$esp
        part=$PART_efi
        fsmod=fat
    fi
    dir=$m/android
    mkdir -p "$dir"

    [ "$MOUNT_SYSTEM" = std_parts ] || install_system "$dir" 5 75
    install_boot_files "$dir" 80
    [ "$2" = 1 ] && install_userdata_files "$dir" 90

    si_progress 96 "Adding the boot entries"
    grubcfg_disk "$(si_title)" "$(si_blkid "$part" UUID)" "$fsmod" "$CMDLINE" "$INSTALL_FIRMWARE" \
        "$MOUNT_SYSTEM" "$MOUNT_USERDATA" "$MOUNT_OVERLAY" >"$esp/EFI/BOOT/grub.cfg"
    si_save_log "$dir"
    sync
    [ "$m" = "$esp" ] || si_umount "$m"
    si_umount "$esp"
    sync
    si_progress 100 "Done"
}
