/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer;

parcelable DrmDevice {
    /** Name of the kernel driver, like i915 or amdgpu */
    @utf8InCpp String driver;
    /** Has a render node, so it can render */
    boolean render;
    /** Has a connector with a monitor connected, so it can display */
    boolean connected;
}
