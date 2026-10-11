/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer;

parcelable Partition {
    @utf8InCpp String name;
    @utf8InCpp String disk;
    long sizeBytes;
    @utf8InCpp String fsType;
    @utf8InCpp String label;
    /** -1 when it could not be mounted */
    long freeMiB;
    /** For an installation beside another operating system, reason says why not */
    boolean usable;
    /** Operating system found on it */
    @utf8InCpp String os;
    @utf8InCpp String reason;
    /** Has the firmware directory of a Linux system, see InstallRequest.firmware */
    boolean linuxFirmware;
}
