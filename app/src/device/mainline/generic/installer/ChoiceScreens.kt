/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

@file:OptIn(ExperimentalMaterial3ExpressiveApi::class)

package device.mainline.generic.installer

import android.content.Context
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Album
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.SdCard
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.SystemUpdate
import androidx.compose.material.icons.outlined.Usb
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp

@Composable
fun LoadingScreen() {
    Centered {
        LoadingIndicator(Modifier.size(96.dp))
        Spacer(Modifier.height(24.dp))
        Text(stringResource(R.string.loading), style = MaterialTheme.typography.titleMedium)
    }
}

/** What to do: whole disk, beside another operating system, upgrade */
@Composable
fun ModesScreen(w: Wizard, onNext: () -> Unit, onClose: () -> Unit) {
    val s = w.probe.system
    val firmware = if (s.uefi) stringResource(R.string.firmware_uefi, s.efiBits)
                   else stringResource(R.string.firmware_bios)
    val modes = listOf(
        Choice("${InstallRequest.MODE_DISK}", Icons.Outlined.Storage,
            stringResource(R.string.mode_disk), stringResource(R.string.mode_disk_summary), s.sourceFound),
        Choice("${InstallRequest.MODE_BESIDE}", Icons.Outlined.Computer,
            stringResource(R.string.mode_beside), stringResource(R.string.mode_beside_summary), s.sourceFound),
        Choice("${InstallRequest.MODE_UPGRADE}", Icons.Outlined.SystemUpdate,
            stringResource(R.string.mode_upgrade), stringResource(R.string.mode_upgrade_summary), s.sourceFound),
    )
    ListPage(
        title = stringResource(R.string.app_name),
        subtitle = stringResource(R.string.system_subtitle, s.title, s.device, firmware),
        primary = Action(stringResource(R.string.next), s.sourceFound, onNext),
        secondary = Action(stringResource(R.string.close), onClick = onClose),
    ) {
        if (s.secureBoot == 1) item { Notice(stringResource(R.string.secure_boot_on)) }
        if (!s.sourceFound) item { Notice(stringResource(R.string.no_source, s.sourceMessage)) }
        item { SectionTitle(stringResource(R.string.mode_title)) }
        choices(modes, "${w.mode}") { w.mode = it.toInt() }
    }
}

fun diskType(type: String) = when (type) {
    "nvme" -> R.string.disk_nvme
    "ssd" -> R.string.disk_ssd
    "hdd" -> R.string.disk_hdd
    "usb" -> R.string.disk_usb
    "sd" -> R.string.disk_sd
    "emmc" -> R.string.disk_emmc
    "ufs" -> R.string.disk_ufs
    "virtio", "xen" -> R.string.disk_virtual
    else -> R.string.disk_other
}

/** Lines of a summary, without the empty ones */
private fun lines(vararg lines: String) = lines.filter(String::isNotEmpty).joinToString("\n")

private fun targetChoices(w: Wizard, context: Context): List<Choice> {
    val p = w.probe
    return when (w.mode) {
        InstallRequest.MODE_DISK -> p.disks.map {
            Choice(
                it.name,
                when (it.type) {
                    "usb" -> Icons.Outlined.Usb
                    "sd" -> Icons.Outlined.SdCard
                    else -> Icons.Outlined.Storage
                },
                "${context.getString(diskType(it.type))} · ${formatBytes(it.sizeBytes)}",
                lines(listOf(it.model, it.name).filter(String::isNotEmpty).joinToString(" · "),
                    if (it.usable) "" else it.reason),
                it.usable,
            )
        }
        InstallRequest.MODE_BESIDE -> p.partitions.map {
            val free = if (it.freeMiB < 0) "?" else formatMiB(it.freeMiB)
            Choice(
                it.name,
                when {
                    it.fsType == "iso9660" || it.fsType == "udf" -> Icons.Outlined.Album
                    it.os.isNotEmpty() -> Icons.Outlined.Computer
                    else -> Icons.Outlined.Storage
                },
                "${it.name} · ${it.fsType.uppercase().ifEmpty { "?" }} · ${formatBytes(it.sizeBytes)}",
                lines(it.os.ifEmpty { it.label }, context.getString(R.string.free, free),
                    if (it.usable) "" else it.reason),
                it.usable,
            )
        }
        else -> p.installations.map {
            val kind = when (it.kind) {
                Installation.KIND_DISK -> R.string.kind_disk
                Installation.KIND_BESIDE -> R.string.kind_beside
                else -> R.string.kind_package
            }
            Choice(
                it.id, Icons.Outlined.SystemUpdate,
                "${it.id} · ${context.getString(kind)}",
                lines(context.getString(R.string.built, formatDate(it.buildDateUtc)), if (it.upgradable) "" else it.reason),
                it.upgradable,
            )
        }
    }
}

/** The disk, partition or installation */
@Composable
fun TargetsScreen(w: Wizard, onNext: () -> Unit, onBack: () -> Unit) {
    val list = targetChoices(w, LocalContext.current)
    if (list.none { it.id == w.target && it.enabled }) w.target = ""
    val title = when (w.mode) {
        InstallRequest.MODE_DISK -> R.string.target_disk
        InstallRequest.MODE_BESIDE -> R.string.target_beside
        else -> R.string.target_upgrade
    }
    ListPage(
        title = stringResource(title),
        primary = Action(stringResource(R.string.next), w.target.isNotEmpty(), onNext),
        secondary = Action(stringResource(R.string.back), onClick = onBack),
    ) {
        if (list.isEmpty()) {
            item { Text(stringResource(R.string.target_none), style = MaterialTheme.typography.bodyLarge) }
        } else {
            choices(list, w.target) { w.target = it }
        }
    }
}

/** What is going to happen; erasing a disk needs its name typed */
@Composable
fun ConfirmScreen(w: Wizard, onInstall: () -> Unit, onBack: () -> Unit) {
    var typed by remember { mutableStateOf("") }
    val title = w.probe.system.title
    ListPage(
        title = stringResource(R.string.confirm_title),
        primary = Action(stringResource(R.string.install), !w.isDisk || typed == w.target, onInstall),
        secondary = Action(stringResource(R.string.back), onClick = onBack),
    ) {
        item {
            when (w.mode) {
                InstallRequest.MODE_DISK -> {
                    val disk = w.probe.disks.firstOrNull { it.name == w.target }
                    val what = listOfNotNull(
                        disk?.let { stringResource(diskType(it.type)) },
                        disk?.model?.takeIf { it.isNotEmpty() },
                        formatBytes(disk?.sizeBytes ?: 0),
                    ).joinToString(" · ")
                    Notice(stringResource(R.string.confirm_disk, w.target, what))
                }
                InstallRequest.MODE_BESIDE -> Summary(stringResource(R.string.confirm_beside, title, w.target))
                else -> Summary(stringResource(R.string.confirm_upgrade, w.target, title))
            }
        }
        if (w.isDisk) {
            item {
                OutlinedTextField(
                    value = typed,
                    onValueChange = { typed = it.trim() },
                    label = { Text(stringResource(R.string.confirm_type, w.target)) },
                    singleLine = true,
                    isError = typed.isNotEmpty() && typed != w.target,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}
