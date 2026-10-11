/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer;

import device.mainline.generic.installer.PartitionSize;

/** The options of scripts/systeminstaller.sh. Strings are never null, "" for the default. */
parcelable InstallRequest {
    /** Wipe the disk target */
    const int MODE_DISK = 0;
    /** Add to the filesystem of partition target */
    const int MODE_BESIDE = 1;
    /** Upgrade the installation target (a disk or a partition) */
    const int MODE_UPGRADE = 2;

    int mode;
    @utf8InCpp String target = "";
    /** Kernel command line without the boot method, "" for the running one's */
    @utf8InCpp String cmdline = "";
    /** MODE_DISK: androidboot.mount_system, "std_parts", "imgs" or "imgs_ram" */
    @utf8InCpp String mountSystem = "";
    /**
     * androidboot.mount_userdata. MODE_DISK: "std_parts", "imgs" or "bind_mount_dir";
     * MODE_BESIDE: "imgs" or "bind_mount_dir" (always "imgs" on NTFS)
     */
    @utf8InCpp String mountUserdata = "";
    /** MODE_DISK: androidboot.mount_overlay, "std_parts", "imgs", "imgs_ram", "dirs" or "" for none */
    @utf8InCpp String mountOverlay = "";
    /** "ext4" or "f2fs": the userdata partition or userdata.img */
    @utf8InCpp String userdataFs = "ext4";
    /** Size of userdata.img */
    int userdataSizeMiB = 16384;
    /** MODE_DISK: filesystem of the android partition, "ext4" or "f2fs" */
    @utf8InCpp String androidFs = "ext4";
    /**
     * MODE_BESIDE: "img" for a firmware image, "linux" for the firmware directory of the Linux
     * system on the partition, or "" for the default (img)
     */
    @utf8InCpp String firmware = "";
    /** MODE_DISK: sizes instead of the defaults (see PartitionLayout) */
    PartitionSize[] sizes = {};
    /** MODE_BESIDE, and MODE_UPGRADE of such an installation */
    boolean bootEntries = true;
    /** MODE_UPGRADE */
    boolean allowDowngrade;
}
