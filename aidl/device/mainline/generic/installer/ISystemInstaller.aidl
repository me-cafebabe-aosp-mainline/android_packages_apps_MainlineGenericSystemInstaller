/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer;

import device.mainline.generic.installer.IProgressCallback;
import device.mainline.generic.installer.InstallRequest;
import device.mainline.generic.installer.ProbeResult;

/**
 * Registered as "device.mainline.generic.installer.ISystemInstaller/default"
 * by systeminstallerd, a lazy service. Only the system UID may call it.
 */
interface ISystemInstaller {
    /** Fails with EX_ILLEGAL_STATE while an installation runs */
    ProbeResult probe();

    /** Fails with EX_ILLEGAL_STATE while an installation runs */
    void start(in InstallRequest request, IProgressCallback callback);

    /** Returns false if nothing runs, or once onDestructive() was called */
    boolean cancel();

    boolean isRunning();
}
