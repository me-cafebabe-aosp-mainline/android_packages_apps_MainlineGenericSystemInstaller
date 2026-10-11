#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# GRUB BIOS boot code for a GPT disk, what grub-bios-setup does: boot.img
# goes to the boot sector, core.img to the BIOS boot partition, and both
# are patched with where core.img is. Shared with the disk image build.
#

# bootcode_write_le <file> <offset> <bytes, at most 4> <value>
bootcode_write_le() {
    local s i
    s=
    i=0
    while [ "$i" -lt "$3" ]; do
        s="$s$(printf '\\%03o' $((($4 >> (8 * i)) & 255)))"
        i=$((i + 1))
    done
    # shellcheck disable=SC2059
    printf "$s" | dd of="$1" bs=1 seek="$2" conv=notrunc 2>/dev/null
}

# bootcode_install <disk> <boot.img> <core.img> <first sector of the BIOS
# boot partition>
bootcode_install() {
    local disk start sectors
    disk=$1
    start=$4

    # Boot sector: GRUB code up to the disk signature, the protective MBR
    # partition table stays.
    dd if="$2" of="$disk" bs=440 count=1 conv=notrunc 2>/dev/null || return 1
    # Sector of core.img (64 bits, the high half stays 0)
    bootcode_write_le "$disk" $((0x5c)) 4 "$start"
    # Hard disk: no drive check (two NOPs over the jump)
    printf '\220\220' | dd of="$disk" bs=1 seek=$((0x66)) conv=notrunc 2>/dev/null

    sectors=$((($(wc -c <"$3") + 511) / 512))
    dd if="$3" of="$disk" bs=512 seek="$start" conv=notrunc 2>/dev/null || return 1
    # First block list of diskboot.img: the rest of core.img
    bootcode_write_le "$disk" $((start * 512 + 0x1f4)) 4 $((start + 1))
    bootcode_write_le "$disk" $((start * 512 + 0x1f8)) 4 0
    bootcode_write_le "$disk" $((start * 512 + 0x1fc)) 2 $((sectors - 1))
}
