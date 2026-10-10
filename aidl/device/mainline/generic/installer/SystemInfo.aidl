/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer;

parcelable SystemInfo {
    boolean uefi;
    /** 64 or 32, 0 when unknown */
    int efiBits;
    /** 1 or 0, -1 when unknown */
    int secureBoot;
    @utf8InCpp String arch;
    @utf8InCpp String device;
    long buildDateUtc;
    @utf8InCpp String title;
    /** Kernel command line of the running system, without the boot method */
    @utf8InCpp String defaultCmdline;
    /** Whether what gets installed was found, sourceMessage says why not */
    boolean sourceFound;
    @utf8InCpp String sourceMessage;
}
