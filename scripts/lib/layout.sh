#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Partition layout of a whole disk installation. Shared by the installer
# (mksh, 32-bit arithmetic) and the disk image build (host sh): sizes are
# in MiB, never in bytes.
#
# Partitions, in this order (the BIOS boot partition only with BIOS boot
# code, the GRUB core.img expects the EFI system partition as gpt2):
#
#   bios efi system system_dlkm vendor vendor_dlkm [<part>_overlay...]
#   metadata userdata
#
# The overlay partitions (androidboot.mount_overlay=std_parts) are optional:
# those of the partitions in LAYOUT_OVERLAYS, empty by default.
#

# Default sizes in MiB: twice the content, at least these, so that later
# builds still fit. The sizes can be changed, down to the content.
LAYOUT_MIN_efi=1024
LAYOUT_MIN_system=4096
LAYOUT_MIN_system_dlkm=128
LAYOUT_MIN_vendor=512
LAYOUT_MIN_vendor_dlkm=512
LAYOUT_SIZE_bios=1
LAYOUT_SIZE_metadata=64
# FAT32 needs at least 33 MiB, user data at least this
LAYOUT_HARD_MIN_efi=64
LAYOUT_HARD_MIN_metadata=16
LAYOUT_HARD_MIN_system_overlay=16
LAYOUT_HARD_MIN_vendor_overlay=16
LAYOUT_MIN_USERDATA=4096

LAYOUT_SYSTEM_PARTS="system system_dlkm vendor vendor_dlkm"
# Partitions that can get an overlay partition, and those that get one
LAYOUT_OVERLAY_PARTS="system vendor"
LAYOUT_OVERLAYS=

# layout_overlays: names of the overlay partitions to create
layout_overlays() {
    local p
    for p in $LAYOUT_OVERLAYS; do
        echo "${p}_overlay"
    done
}

# layout_parts <bios: 0|1>
layout_parts() {
    if [ "$1" = 1 ]; then
        echo bios efi $LAYOUT_SYSTEM_PARTS $(layout_overlays) metadata userdata
    else
        echo efi $LAYOUT_SYSTEM_PARTS $(layout_overlays) metadata userdata
    fi
}

# layout_number <bios: 0|1> <name>: partition number
layout_number() {
    local n p
    n=1
    for p in $(layout_parts "$1"); do
        if [ "$p" = "$2" ]; then
            echo $n
            return 0
        fi
        n=$((n + 1))
    done
    return 1
}

# layout_minimum <name> <content MiB>: the smallest size it can have
layout_minimum() {
    local min
    eval "min=\${LAYOUT_HARD_MIN_$1:-1}"
    if [ "$2" -gt "$min" ]; then
        echo "$2"
    else
        echo "$min"
    fi
}

# layout_size <name> <content MiB>: default size, twice the content, at
# least LAYOUT_MIN_<name>
layout_size() {
    local min size
    eval "min=\${LAYOUT_MIN_$1:-0}"
    size=$(($2 * 2))
    [ "$size" -ge "$min" ] || size=$min
    echo "$size"
}

# layout_create <sgdisk> <target> <bios: 0|1> <size of each partition after
# bios, in MiB, in layout_parts order; 0 for userdata takes the rest>
layout_create() {
    local sgdisk target bios args n p size end
    sgdisk=$1
    target=$2
    bios=$3
    shift 3

    "$sgdisk" --zap-all "$target" >/dev/null 2>&1 || true
    set -- $( [ "$bios" = 1 ] && echo "$LAYOUT_SIZE_bios" ) "$@"
    args=
    n=1
    for p in $(layout_parts "$bios"); do
        size=$1
        shift
        case $p in
        bios) type=ef02 ;;
        efi) type=ef00 ;;
        *) type=8300 ;;
        esac
        if [ "$size" = 0 ]; then
            end=0
        else
            end=+${size}M
        fi
        args="$args --new=$n:0:$end --typecode=$n:$type --change-name=$n:$p"
        n=$((n + 1))
    done
    "$sgdisk" $args "$target" >/dev/null
}

# layout_first_sector <sgdisk> <target> <number>. Long options only: the
# sgdisk of Android does not take short ones.
layout_first_sector() {
    "$1" --info="$3" "$2" | sed -n 's/^First sector: \([0-9]*\).*/\1/p'
}
