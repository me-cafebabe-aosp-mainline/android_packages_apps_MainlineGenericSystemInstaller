/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer

import android.os.ServiceManager

/** systeminstallerd, started on demand by servicemanager */
object Installer {
    private const val SERVICE = "device.mainline.generic.installer.ISystemInstaller/default"

    fun get(): ISystemInstaller? =
        ServiceManager.waitForService(SERVICE)?.let { ISystemInstaller.Stub.asInterface(it) }
}
