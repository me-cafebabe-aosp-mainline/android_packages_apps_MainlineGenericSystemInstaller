/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer;

/** A partition of a whole disk installation, except userdata (the rest) */
parcelable PartitionLayout {
    @utf8InCpp String name;
    int defaultMiB;
    /** What it has to hold */
    int minimumMiB;
}
