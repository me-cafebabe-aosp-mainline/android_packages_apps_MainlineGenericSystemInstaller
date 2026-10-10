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
    /** Size of userdata.img, for MODE_BESIDE on NTFS */
    int userdataSizeMiB = 16384;
    /** Kernel command line without the boot method, empty for the default */
    @utf8InCpp String cmdline;
    /** For MODE_BESIDE and MODE_UPGRADE of such an installation */
    boolean bootEntries = true;
    boolean allowDowngrade;
    /** For MODE_DISK: sizes instead of the defaults */
    PartitionSize[] sizes = {};
}
