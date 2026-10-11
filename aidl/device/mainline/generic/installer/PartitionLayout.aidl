/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer;

/**
 * A partition of a whole disk installation (a LAYOUT record of the probe). Not the last one,
 * userdata or android, which takes the rest. android: only before metadata and userdata, with
 * system images. efi_android: efi with an android partition, which holds the kernel.
 */
parcelable PartitionLayout {
    @utf8InCpp String name;
    /** 0: optional (overlay partitions), only created with a size */
    int defaultMiB;
    /** What it has to hold */
    int minimumMiB;
}
