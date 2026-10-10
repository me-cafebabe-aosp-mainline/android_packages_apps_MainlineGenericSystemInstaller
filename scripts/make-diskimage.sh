#!/bin/sh
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Builds the flashable disk image on the build host: the same layout and
# boot files as a whole disk installation.
#
# Usage: make-diskimage.sh <options>
#   --out <file>                 disk image to write
#   --sgdisk <path>              host sgdisk
#   --mke2fs <path>              host mke2fs
#   --mtools <path>              mtools binary (run as mformat, mmd, mcopy)
#   --loader <path>              dynamic loader to run mtools with (optional)
#   --grub <dir>                 /system_ext/etc/systeminstaller/grub of the build
#   --kernel <file>
#   --ramdisk <file>
#   --firmware <file>            firmware image (optional)
#   --image <name>=<file>        system, system_dlkm, vendor, vendor_dlkm
#   --title <text>               GRUB menu title
#   --cmdline <text>             kernel command line
#   --userdata-size <MiB>
#   --serial <8 hex digits>      volume serial of the EFI system partition
#

set -e

LIB=$(dirname "$0")/lib
. "$LIB/layout.sh"
. "$LIB/bootcode.sh"
. "$LIB/grubcfg.sh"

firmware=
loader=
serial=4e4d4c47
while [ $# -gt 0 ]; do
    case $1 in
    --out) out=$2 ;;
    --sgdisk) sgdisk=$2 ;;
    --mke2fs) mke2fs=$2 ;;
    --mtools) mtools=$2 ;;
    --loader) loader=$2 ;;
    --grub) grub=$2 ;;
    --kernel) kernel=$2 ;;
    --ramdisk) ramdisk=$2 ;;
    --firmware) firmware=$2 ;;
    --image) eval "image_${2%%=*}=\${2#*=}" ;;
    --title) title=$2 ;;
    --cmdline) cmdline=$2 ;;
    --userdata-size) userdata_size=$2 ;;
    --serial) serial=$2 ;;
    *) echo "make-diskimage.sh: unknown option $1" >&2; exit 1 ;;
    esac
    shift 2
done

mtool() {
    local tool
    tool=$1
    shift
    if [ -n "$loader" ]; then
        "$loader" --library-path "${loader%/*}" --argv0 "$tool" "$mtools" "$@"
    else
        "$mtools" -c "$tool" "$@"
    fi
}

mib() {
    echo $((($(wc -c <"$1") + 1048575) / 1048576))
}

bios=0
[ -f "$grub/i386-pc-core.img" ] && bios=1

esp_content=$(($(mib "$kernel") + $(mib "$ramdisk") + 16))
[ -n "$firmware" ] && esp_content=$((esp_content + $(mib "$firmware")))
sizes="$(layout_size esp $esp_content)"
for p in $LAYOUT_SYSTEM_PARTS; do
    eval "file=\$image_$p"
    sizes="$sizes $(layout_size $p "$(mib "$file")")"
done
sizes="$sizes $LAYOUT_SIZE_metadata $userdata_size"

total=2
for s in $sizes; do
    total=$((total + s))
done
[ "$bios" = 1 ] && total=$((total + LAYOUT_SIZE_bios))

rm -f "$out"
truncate -s "${total}M" "$out"
layout_create "$sgdisk" "$out" "$bios" $sizes

start() {
    layout_first_sector "$sgdisk" "$out" "$(layout_number "$bios" "$1")"
}

for p in $LAYOUT_SYSTEM_PARTS; do
    eval "file=\$image_$p"
    dd if="$file" of="$out" bs=1M seek=$(($(start $p) / 2048)) conv=notrunc 2>/dev/null
done

for p in metadata userdata; do
    if [ $p = metadata ]; then size=$LAYOUT_SIZE_metadata; else size=$userdata_size; fi
    "$mke2fs" -q -F -t ext4 -b 4096 -I 256 -L $p -E offset=$(($(start $p) * 512)) "$out" "${size}M"
done

esp_size=${sizes%% *}
esp="$out@@$(($(start esp) * 512))"
mtool mformat -i "$esp" -F -T $((esp_size * 2048)) -N "$serial" -v ESP ::
mtool mmd -i "$esp" ::/EFI ::/EFI/BOOT ::/android
if [ "$bios" = 1 ]; then
    mtool mcopy -i "$esp" "$grub/x86_64-efi.efi" ::/EFI/BOOT/BOOTX64.EFI
    mtool mcopy -i "$esp" "$grub/i386-efi.efi" ::/EFI/BOOT/BOOTIA32.EFI
else
    mtool mcopy -i "$esp" "$grub/arm64-efi.efi" ::/EFI/BOOT/BOOTAA64.EFI
fi
mtool mcopy -i "$esp" "$grub/unicode.pf2" ::/EFI/BOOT/unicode.pf2
mtool mcopy -i "$esp" "$kernel" ::/android/kernel
mtool mcopy -i "$esp" "$ramdisk" ::/android/ramdisk-all-combined.img
[ -n "$firmware" ] && mtool mcopy -i "$esp" "$firmware" ::/android/firmware.img

uuid=$(echo "$serial" | sed 's/\(....\)\(....\)/\1-\2/' | tr a-f A-F)
cfg=$(mktemp)
grubcfg_disk "$title" "$uuid" "$cmdline" "$([ -n "$firmware" ] && echo 1 || echo 0)" >"$cfg"
mtool mcopy -i "$esp" "$cfg" ::/EFI/BOOT/grub.cfg
rm -f "$cfg"

if [ "$bios" = 1 ]; then
    bootcode_install "$out" "$grub/i386-pc-boot.img" "$grub/i386-pc-core.img" "$(start bios)"
fi
