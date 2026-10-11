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
    /** Size of userdata.img, for MODE_BESIDE with images */
    int userdataSizeMiB = 16384;
    /**
     * Filesystem of userdata, "ext4" or "f2fs": for MODE_DISK, and for
     * MODE_BESIDE with images (userdata.img)
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
     * For MODE_DISK: androidboot.mount_overlay, "std_parts" (overlay
     * partitions, given a size in sizes), "imgs", "imgs_ram", or empty for
     * none. Not "dirs": overlayfs refuses directories on FAT32.
     */
    @utf8InCpp String overlay = "";
}
