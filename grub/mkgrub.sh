#!/bin/bash
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Builds a GRUB image with the GRUB tools from prebuilts/bootmgr.
#
# Usage: mkgrub.sh <out> <platform> <embedded config> <files...>
#
# <files...> are the files of the bootmgr_lib64 and
# bootmgr_grub_linux-x86_<platform> filegroups. EFI platforms get a
# standalone image (modules in a memdisk), i386-pc gets a core.img for a
# BIOS boot partition.
#

set -e

out=$1
platform=$2
config=$3
shift 3

loader=
root=
for file in "$@"; do
    case $file in
    */lib64/ld-linux-x86-64.so.2) loader=$file ;;
    */grub/linux-x86/"$platform"/bin/grub-mkimage) root=${file%/bin/grub-mkimage} ;;
    esac
done
if [ -z "$loader" ] || [ -z "$root" ]; then
    echo "mkgrub.sh: GRUB tools for $platform not found" >&2
    exit 1
fi

run() {
    tool=$1
    shift
    "$loader" --library-path "${loader%/*}" "$root/bin/$tool" "$@"
}

case $platform in
*-efi)
    run grub-mkstandalone -d "$root/lib/grub/$platform" -O "$platform" -o "$out" \
        --locales= --fonts= --themes= \
        --modules="part_gpt part_msdos fat ext2 f2fs ntfs search search_fs_uuid configfile normal linux echo test all_video gfxterm font" \
        "boot/grub/grub.cfg=$config"
    ;;
i386-pc)
    # The prefix is the EFI system partition, the second partition of a
    # whole disk installation.
    run grub-mkimage -d "$root/lib/grub/$platform" -O "$platform" -o "$out" \
        -p "(,gpt2)/EFI/BOOT" -c "$config" \
        biosdisk part_gpt fat search search_fs_uuid configfile normal linux echo test all_video gfxterm font
    ;;
*)
    echo "mkgrub.sh: unsupported platform $platform" >&2
    exit 1
    ;;
esac
