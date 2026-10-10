/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer;

parcelable Installation {
    const int KIND_DISK = 0;
    const int KIND_BESIDE = 1;
    /** Installed by a package of a Linux distribution, not upgradable here */
    const int KIND_PACKAGE = 2;

    /** Disk or partition */
    @utf8InCpp String id;
    int kind;
    long buildDateUtc;
    /** reason says why not */
    boolean upgradable;
    @utf8InCpp String reason;
}
