#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# GRUB configuration of an installation. Shared with the disk image build.
#
# $sidir is set by the embedded configuration of our GRUB images: the
# directory of grub.cfg and unicode.pf2.
#

grubcfg_header() {
    cat <<'EOF2'
set timeout=5
set gfxmode=auto
set gfxpayload=keep
insmod all_video
if loadfont "$sidir/unicode.pf2"; then
    insmod gfxterm
    terminal_output gfxterm
fi

EOF2
}

# grubcfg_entry <title> <filesystem UUID> <GRUB filesystem module>
# <Android directory> <kernel command line>
grubcfg_entry() {
    printf "menuentry '%s' --class android {\n" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
    printf '\tinsmod part_gpt\n\tinsmod part_msdos\n\tinsmod %s\n' "$3"
    printf '\tsearch --no-floppy --fs-uuid --set=root %s\n' "$2"
    printf "\techo 'Loading kernel...'\n"
    printf '\tlinux /%s/kernel %s\n' "$4" "$5"
    printf "\techo 'Loading ramdisk...'\n"
    printf '\tinitrd /%s/ramdisk-all-combined.img\n' "$4"
    printf '}\n'
}

# grubcfg_entries <title> <filesystem UUID> <GRUB filesystem module>
# <Android directory> <kernel command line> <userdata mount method>:
# the entry, and one with user data in RAM. generic_init looks for the
# Android directory on that filesystem only (androidboot.android_dir_dev),
# not on another installation or media.
grubcfg_entries() {
    local cmdline
    cmdline="$5 androidboot.android_dir_dev=UUID=$2"
    grubcfg_entry "$1" "$2" "$3" "$4" "$cmdline androidboot.mount_userdata=$6"
    if [ "$6" != tmpfs ]; then
        grubcfg_entry "$1 (user data in RAM)" "$2" "$3" "$4" "$cmdline androidboot.mount_userdata=tmpfs"
    fi
}

# grubcfg_disk <title> <UUID of the filesystem with the Android directory>
# <its GRUB filesystem module> <kernel command line> <firmware image: 0|1>
# <androidboot.mount_system> <androidboot.mount_userdata>
# [androidboot.mount_overlay]: grub.cfg of a whole disk installation
grubcfg_disk() {
    local cmdline
    cmdline="$4 androidboot.android_dir=android androidboot.mount_system=$6"
    [ "$5" = 1 ] && cmdline="$cmdline androidboot.mount_firmware=img"
    [ -n "$8" ] && cmdline="$cmdline androidboot.mount_overlay=$8"
    grubcfg_header
    grubcfg_entries "$1" "$2" "$3" android "$cmdline" "$7"
}
