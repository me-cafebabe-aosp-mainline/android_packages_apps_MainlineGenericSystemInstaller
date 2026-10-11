/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.SystemProperties

/** Shows the launcher icon on live boots only, Settings > System has the entry otherwise. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val live = SystemProperties.get("ro.boot.live") == "1"
        context.packageManager.setComponentEnabledSetting(
            ComponentName(context, "$PACKAGE.LauncherActivity"),
            if (live) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DEFAULT,
            PackageManager.DONT_KILL_APP,
        )
    }

    companion object {
        const val PACKAGE = "device.mainline.generic.installer"
    }
}
