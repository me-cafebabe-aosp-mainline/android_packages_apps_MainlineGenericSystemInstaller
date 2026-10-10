/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer;

parcelable Disk {
    @utf8InCpp String name;
    long sizeBytes;
    boolean removable;
    /** For a whole disk installation, reason says why not */
    boolean usable;
    @utf8InCpp String model;
    @utf8InCpp String reason;
}
