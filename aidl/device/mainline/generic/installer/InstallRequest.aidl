/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer;

import device.mainline.generic.installer.PartitionSize;

parcelable InstallRequest {
    /** Wipe the disk target */
    const int MODE_DISK = 0;
    /** Add to the filesystem of partition target */
    const int MODE_BESIDE = 1;
    /** Upgrade the installation target (a disk or a partition) */
    const int MODE_UPGRADE = 2;

    int mode;
    @utf8InCpp String target;
    /**
     * For MODE_BESIDE: user data in images (userdata.img, metadata.img)
     * instead of directories. Always on NTFS.
     */
    boolean userdataImages;
    /** Size of userdata.img: MODE_BESIDE with images, MODE_DISK with "imgs" */
    int userdataSizeMiB = 16384;
    /**
     * Filesystem of userdata, "ext4" or "f2fs": the partition or
     * userdata.img
     */
    @utf8InCpp String userdataFs = "ext4";
    /** Kernel command line without the boot method, empty for the default */
    @utf8InCpp String cmdline;
    /** For MODE_BESIDE and MODE_UPGRADE of such an installation */
    boolean bootEntries = true;
    boolean allowDowngrade;
    /** For MODE_DISK: sizes instead of the defaults */
    PartitionSize[] sizes = {};
    /**
     * For MODE_DISK: androidboot.mount_system, "std_parts", "imgs" or
     * "imgs_ram". Images and directories go to an android partition.
     */
    @utf8InCpp String mountSystem = "std_parts";
    /** For MODE_DISK: androidboot.mount_userdata, "std_parts", "imgs" or "bind_mount_dir" */
    @utf8InCpp String mountUserdata = "std_parts";
    /** For MODE_DISK: filesystem of the android partition, "ext4" or "f2fs" */
    @utf8InCpp String androidFs = "ext4";
    /**
     * For MODE_DISK: androidboot.mount_overlay, "std_parts" (overlay
     * partitions, given a size in sizes), "imgs", "imgs_ram", "dirs" (only
     * with an android partition: overlayfs refuses directories on FAT32),
     * or empty for none
     */
    @utf8InCpp String overlay = "";
}
