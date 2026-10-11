/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp

/** Whole disk: where everything goes, and the partition sizes */
@Composable
fun PartitionsScreen(w: Wizard, onNext: () -> Unit, onBack: () -> Unit) {
    val disk = w.probe.disks.firstOrNull { it.name == w.target } ?: return
    val diskMiB = disk.sizeBytes / 1048576
    val rows = w.layoutRows()
    val values = rows.map { w.sizeMiB(it) }
    fun invalid(i: Int) = values[i] < rows[i].layout.minimumMiB && !(rows[i].optional && values[i] == 0L)
    val noOverlayPartition = w.overlay == Mount.PARTITIONS && rows.indices.none { rows[it].optional && values[it] > 0 }
    val restMiB = diskMiB - OVERHEAD_MIB - values.sum()
    val fits = restMiB >= w.restNeedMiB
    val colors = MaterialTheme.colorScheme.let {
        listOf(it.primary, it.secondary, it.tertiary, it.error, it.primaryContainer, it.tertiaryContainer)
    }
    fun color(i: Int) = colors[i % colors.size]
    val restColor = MaterialTheme.colorScheme.surfaceVariant

    ListPage(
        title = stringResource(R.string.partitions_title),
        subtitle = "${disk.name} · ${formatMiB(diskMiB)}",
        primary = Action(
            stringResource(R.string.next),
            rows.indices.none { invalid(it) } && !noOverlayPartition && fits,
            onNext,
        ),
        secondary = Action(stringResource(R.string.back), onClick = onBack),
    ) {
        item { LayoutChoice(w) }
        item { UsageBar(values.indices.map { values[it] to color(it) } + (restMiB to restColor)) }
        item {
            Row(
                Modifier.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Dot(restColor)
                Text(
                    if (fits) stringResource(R.string.partition_rest, w.restPartition, formatMiB(restMiB))
                    else stringResource(R.string.partition_too_small, w.restPartition, formatMiB(w.restNeedMiB)),
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (fits) Color.Unspecified else MaterialTheme.colorScheme.error,
                )
            }
        }
        itemsIndexed(rows) { i, row ->
            // The overlay partitions come last, below the choice of overlays
            if (row.optional && (i == 0 || !rows[i - 1].optional)) OverlayChoice(w, noOverlayPartition)
            if (row.optional && w.overlay != Mount.PARTITIONS) return@itemsIndexed
            val l = row.layout
            OutlinedTextField(
                value = w.sizes[l.name] ?: "${l.defaultMiB}",
                onValueChange = { v -> w.sizes[l.name] = v.filter(Char::isDigit).take(9) },
                label = { Text(row.name) },
                leadingIcon = { Dot(color(i)) },
                suffix = { Text("MiB") },
                supportingText = {
                    Text(
                        if (row.optional) {
                            stringResource(R.string.partition_optional_hint, formatMiB(l.minimumMiB.toLong()))
                        } else {
                            stringResource(R.string.partition_size_hint,
                                formatMiB(l.minimumMiB.toLong()), formatMiB(l.defaultMiB.toLong()))
                        }
                    )
                },
                isError = invalid(i),
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            TextButton(onClick = { w.sizes.clear() }, enabled = w.sizes.isNotEmpty()) {
                Text(stringResource(R.string.reset_sizes))
            }
        }
    }
}

/** System and user data: partitions, or images and directories in an android partition */
@Composable
private fun LayoutChoice(w: Wizard) {
    Column(Modifier.padding(bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionTitle(stringResource(R.string.layout_system))
        ChipChoice(SYSTEM_MOUNTS, w.systemMount, { stringResource(it.label) }) { w.systemMount = it }
        SectionTitle(stringResource(R.string.layout_userdata))
        ChipChoice(DISK_USERDATA_MOUNTS, w.diskUserdataMount, { stringResource(it.label) }) {
            w.diskUserdataMount = it
        }
        if (w.diskUserdataMount == Mount.IMAGES) UserdataSize(w)
        if (w.hasUserdataFs) {
            SectionTitle(stringResource(R.string.userdata_fs))
            ChipChoice(Fs.entries, w.userdataFs, { it.label }) { w.userdataFs = it }
        }
        if (w.hasAndroidPartition) {
            SectionTitle(stringResource(R.string.android_fs))
            ChipChoice(Fs.entries, w.androidFs, { it.label }) { w.androidFs = it }
        }
        Hint(stringResource(
            if (w.hasAndroidPartition) R.string.layout_android_summary else R.string.layout_partitions_summary
        ))
    }
}

/** androidboot.mount_overlay, above the sizes of overlay partitions */
@Composable
private fun OverlayChoice(w: Wizard, noOverlayPartition: Boolean) {
    Column(Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionTitle(stringResource(R.string.overlays))
        ChipChoice(w.overlayMounts, w.overlay, { stringResource(it.label) }) { w.overlayMount = it }
        Hint(
            stringResource(
                when (w.overlay) {
                    Mount.PARTITIONS -> R.string.overlay_partitions_summary
                    Mount.IMAGES -> if (w.hasAndroidPartition) R.string.overlay_images_android_summary
                                    else R.string.overlay_images_summary
                    Mount.IMAGES_RAM -> R.string.overlay_images_ram_summary
                    Mount.DIRECTORIES -> R.string.overlay_dirs_summary
                    else -> R.string.overlay_none_summary
                }
            ),
            error = noOverlayPartition,
        )
    }
}

@Composable
fun UserdataSize(w: Wizard) {
    OutlinedTextField(
        value = w.userdataGiB,
        onValueChange = { v -> w.userdataGiB = v.filter(Char::isDigit) },
        label = { Text(stringResource(R.string.userdata_size)) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
}
