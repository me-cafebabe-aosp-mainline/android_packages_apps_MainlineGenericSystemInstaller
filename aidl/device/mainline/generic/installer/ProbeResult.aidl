/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer;

import device.mainline.generic.installer.Disk;
import device.mainline.generic.installer.Installation;
import device.mainline.generic.installer.Partition;
import device.mainline.generic.installer.SystemInfo;

parcelable ProbeResult {
    SystemInfo system;
    Disk[] disks;
    Partition[] partitions;
    Installation[] installations;
}
