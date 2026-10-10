#!/system/bin/sh
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Installs the running system. Run by systeminstallerd, as root.
#
# Usage:
#   systeminstaller probe
#   systeminstaller install-disk --target <disk> [--cmdline <text>]
#       [--size <partition>=<MiB>]...
#   systeminstaller install-beside --target <partition> [--userdata-size <MiB>]
#       [--cmdline <text>] [--no-boot-entries]
#   systeminstaller upgrade --target <disk or partition> [--cmdline <text>]
#       [--no-boot-entries] [--allow-downgrade]
#

SI_ETC=${SI_ETC:-/system_ext/etc/systeminstaller}
for lib in common layout bootcode grubcfg source probe install; do
    . "$SI_ETC/lib/$lib.sh"
done

command=$1
[ $# -gt 0 ] && shift
target=
cmdline=
userdata_size=16384
boot_entries=1
allow_downgrade=0
while [ $# -gt 0 ]; do
    case $1 in
    --target) target=$2; shift ;;
    --cmdline) cmdline=$2; shift ;;
    --userdata-size) userdata_size=$2; shift ;;
    --no-boot-entries) boot_entries=0 ;;
    --allow-downgrade) allow_downgrade=1 ;;
    --size)
        case ${2%%=*} in
        efi | system | system_dlkm | vendor | vendor_dlkm | metadata) eval "SIZE_${2%%=*}=\${2#*=}" ;;
        *) si_die "Unknown partition ${2%%=*}" ;;
        esac
        shift
        ;;
    *) si_die "Unknown option $1" ;;
    esac
    shift
done
[ -n "$cmdline" ] || cmdline=$(si_default_cmdline)

case $command in
probe)
    probe
    ;;
install-disk)
    install_disk "$target" "$cmdline" 0 0
    ;;
install-beside)
    install_beside "$target" "$userdata_size" "$cmdline" "$boot_entries" 0 0
    ;;
upgrade)
    if [ -f "/sys/class/block/$target/partition" ]; then
        install_beside "$target" 0 "$cmdline" "$boot_entries" 1 "$allow_downgrade"
    else
        install_disk "$target" "$cmdline" 1 "$allow_downgrade"
    fi
    ;;
*)
    si_die "Unknown command $command"
    ;;
esac
