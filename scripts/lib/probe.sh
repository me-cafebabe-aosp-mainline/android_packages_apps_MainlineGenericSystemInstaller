#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# probe prints, tab separated:
#
#   LAYOUT  <partition> <default MiB> <minimum MiB>   of a whole disk
#           installation, userdata takes the rest. A default of 0: optional,
#           not created unless given a size
#   SERIAL  <name>   a serial port, or a virtio console (hvc)
#   SYSTEM  <uefi|bios> <EFI bits: 64|32|> <Secure Boot: 1|0|> <arch>
#           <device> <build date> <title> <default kernel command line>
#           <source found: 1|0> <why not>
#   DISK    <name> <bytes> <removable: 1|0> <usable: 1|0> <vendor and
#           model> <why not> <type, see si_disk_type>
#   PART    <name> <disk> <bytes> <filesystem> <label> <free MiB>
#           <usable: 1|0> <operating system> <why not>
#   INSTALL <id> <disk|beside|package> <build date> <upgradable: 1|0>
#           <why not>
#
# "usable" is for a whole disk installation (DISK) or an installation
# beside another operating system (PART).
#

# Sets MIB_<name> for what gets installed (MIB_efi: the content of the EFI
# system partition), and MIB_DISK and MIB_BESIDE, the minimum sizes for both
# kinds of installation with the default partition sizes
probe_sizes() {
    local p dev mib
    MIB_kernel=$(si_mib "$(wc -c <"$SRC_DIR/kernel")")
    MIB_ramdisk=$(si_mib "$(wc -c <"$SRC_DIR/ramdisk-all-combined.img")")
    MIB_firmware=$(source_firmware_mib)
    MIB_efi=$((MIB_kernel + MIB_ramdisk + MIB_firmware + 16))
    MIB_DISK=$((2 + LAYOUT_SIZE_metadata + LAYOUT_MIN_USERDATA))
    [ -f "$SI_GRUB/i386-pc-core.img" ] && MIB_DISK=$((MIB_DISK + LAYOUT_SIZE_bios))
    MIB_DISK=$((MIB_DISK + $(layout_size efi "$MIB_efi")))
    MIB_BESIDE=$((MIB_kernel + MIB_ramdisk + MIB_firmware + 64))
    for p in $LAYOUT_SYSTEM_PARTS; do
        eval "dev=\$SRC_$p"
        mib=0
        [ -n "$dev" ] && mib=$(si_mib "$(si_fs_size "/dev/block/$dev")")
        eval "MIB_$p=\$mib"
        MIB_DISK=$((MIB_DISK + $(layout_size "$p" "$mib")))
        MIB_BESIDE=$((MIB_BESIDE + mib))
    done
}

probe_secure_boot() {
    local vars f
    vars=/sys/firmware/efi/efivars
    [ -d "$vars" ] || return
    [ -n "$(ls -A "$vars" 2>/dev/null)" ] || mount -t efivarfs -o ro none "$vars" 2>/dev/null
    f=$(ls "$vars"/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null) || return
    od -A n -t u1 -j 4 -N 1 "$f" | tr -d ' '
}

probe_system() {
    local firmware bits
    if [ -d /sys/firmware/efi ]; then
        firmware=uefi
        bits=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null)
    else
        firmware=bios
        bits=
    fi
    printf 'SYSTEM\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$firmware" "$bits" \
        "$(probe_secure_boot)" "$(uname -m)" "$(si_device)" "$(getprop ro.build.date.utc)" \
        "$(si_title)" "$(si_default_cmdline)" "$1" "$SRC_MSG"
}

# probe_os <mount point>
probe_os() {
    local name
    if [ -f "$1/etc/os-release" ]; then
        name=$(sed -n 's/^PRETTY_NAME=//p' "$1/etc/os-release" | tr -d '"')
        echo "${name:-Linux}"
    elif [ -d "$1/Windows/System32" ]; then
        echo Windows
    elif [ -d "$1/EFI" ]; then
        echo "EFI system partition"
    fi
}

# probe_install_date <disk>: build date of a whole disk installation on
# it, or nothing
probe_install_date() {
    local system esp userdata p
    system=
    esp=
    userdata=
    for p in $(si_partitions "$1"); do
        case $(si_partname "$p") in
        system) system=$p ;;
        efi | esp) esp=$p ;;
        userdata) userdata=$p ;;
        esac
    done
    [ -n "$system" ] && [ -n "$esp" ] && [ -n "$userdata" ] || return 1
    si_build_date "/dev/block/$system"
}

probe_serial_ports() {
    local t n
    for t in /sys/class/tty/*; do
        n=${t##*/}
        case $n in
        ttyS[0-9]*)
            # 8250 also registers ports that are not there, of type 0
            [ "$(cat "$t/type" 2>/dev/null)" != 0 ] || continue
            ;;
        # All of them are registered, the ones without a backend (virtio
        # console...) can not be opened
        hvc[0-9]*) (exec 3<"/dev/$n") 2>/dev/null || continue ;;
        tty | tty[0-9]* | ttynull) continue ;;
        tty*) [ -e "$t/device" ] || continue ;;
        *) continue ;;
        esac
        printf 'SERIAL\t%s\n' "$n"
    done
}

probe() {
    local name device found src_disks busy d bytes usable why installed upgradable p disk fstype label free os m
    name=$(si_install_name)
    device=$(si_device)
    if source_find; then
        found=1
        probe_sizes
    else
        found=0
    fi
    probe_system $found
    probe_serial_ports
    if [ "$found" = 1 ]; then
        for p in efi $LAYOUT_SYSTEM_PARTS; do
            eval "mib=\$MIB_$p"
            printf 'LAYOUT\t%s\t%s\t%s\n' "$p" "$(layout_size "$p" "$mib")" "$(layout_minimum "$p" "$mib")"
        done
        printf 'LAYOUT\tmetadata\t%s\t%s\n' "$LAYOUT_SIZE_metadata" "$LAYOUT_HARD_MIN_metadata"
        for p in $LAYOUT_OVERLAY_PARTS; do
            printf 'LAYOUT\t%s_overlay\t0\t%s\n' "$p" "$(layout_minimum "${p}_overlay" 0)"
        done
    fi

    src_disks=$(source_disks 2>/dev/null)
    busy=$(si_busy_disks)

    for d in $(si_disks); do
        bytes=$(si_size "$d")
        usable=0
        why=
        if [ "$found" = 0 ]; then
            why=$SRC_MSG
        elif echo "$src_disks" | grep -qx "$d"; then
            why="The running system is on this disk"
        elif echo "$busy" | grep -qx "$d"; then
            why="A partition of this disk is in use"
        elif [ "$(si_mib "$bytes")" -lt "$MIB_DISK" ]; then
            why="At least $MIB_DISK MiB are needed"
        else
            usable=1
        fi
        printf 'DISK\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$d" "$bytes" \
            "$(cat "/sys/block/$d/removable" 2>/dev/null || echo 0)" "$usable" \
            "$(si_disk_name "$d")" "$why" "$(si_disk_type "$d")"

        installed=$(probe_install_date "$d") || continue
        upgradable=0
        why=
        if echo "$src_disks" | grep -qx "$d"; then
            why="This is the running system"
        elif echo "$busy" | grep -qx "$d"; then
            why="A partition of this disk is in use"
        elif [ "$found" = 0 ]; then
            why=$SRC_MSG
        else
            upgradable=1
        fi
        printf 'INSTALL\t%s\tdisk\t%s\t%s\t%s\n' "$d" "$installed" "$upgradable" "$why"
    done

    for p in $(si_filesystems); do
        disk=$(si_disk_of "$p")
        fstype=$(si_blkid "$p" TYPE)
        label=$(si_blkid "$p" LABEL)
        free=
        os=
        usable=0
        why=
        if si_mount "$p"; then
            m=$SI_MNT
            free=$(si_free "$m")
            os=$(probe_os "$m")
            if [ -f "$m/$name/system.img" ]; then
                installed=$(si_build_date "$m/$name/system.img")
                upgradable=0
                why=
                if [ "$p" = "$SRC_DIR_DEV" ] && [ "$SRC_DIR_NAME" = "$name" ]; then
                    why="This is the running system"
                elif [ "$found" = 0 ]; then
                    why=$SRC_MSG
                else
                    upgradable=1
                fi
                printf 'INSTALL\t%s\tbeside\t%s\t%s\t%s\n' "$p" "$installed" "$upgradable" "$why"
            fi
            if [ -d "$m/usr/lib/android-system/$device" ]; then
                printf 'INSTALL\t%s\tpackage\t\t0\t%s\n' "$p" "Installed by a package, upgrade it with the package manager"
            fi
            si_umount "$m"
        fi
        why=
        case $fstype in
        ext4 | f2fs | ntfs)
            if [ "$found" = 0 ]; then
                why=$SRC_MSG
            elif [ -z "$free" ]; then
                why="The filesystem can not be mounted"
            elif [ "$free" -lt $((MIB_BESIDE + 1024)) ]; then
                why="At least $((MIB_BESIDE + 1024)) MiB of free space are needed"
            else
                usable=1
            fi
            ;;
        *) why="Only EXT4, F2FS and NTFS are supported" ;;
        esac
        printf 'PART\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$p" "$disk" "$(si_size "$p")" \
            "$fstype" "$label" "$free" "$usable" "$os" "$why"
    done
}
