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
    /** Vendor and model, or the card name; may be empty */
    @utf8InCpp String model;
    @utf8InCpp String reason;
    /** nvme, ssd, hdd (SATA), usb, sd, emmc, ufs, virtio, xen or scsi */
    @utf8InCpp String type;
}
