/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp

/** Boot options, user data, the kernel command line */
@Composable
fun OptionsScreen(w: Wizard, onNext: () -> Unit, onBack: () -> Unit) {
    val switches = buildList {
        if (w.hasBootEntries) {
            add(SwitchItem(stringResource(R.string.boot_entries), stringResource(R.string.boot_entries_summary),
                w.bootEntries) { w.bootEntries = it })
        }
        if (w.mode == InstallRequest.MODE_UPGRADE) {
            add(SwitchItem(stringResource(R.string.allow_downgrade), stringResource(R.string.allow_downgrade_summary),
                w.allowDowngrade) { w.allowDowngrade = it })
        }
    }
    @Composable
    fun items(toggles: List<BootToggle>) = toggles.map { t ->
        SwitchItem(stringResource(t.title), stringResource(t.summary), w.hasTokens(t.tokens)) { on ->
            if (on) w.editTokens(t.tokens, emptyList()) else w.editTokens(emptyList(), t.tokens)
        }
    }
    val bootToggles = items(BOOT_TOGGLES)
    val graphicsToggles = items(GRAPHICS_TOGGLES)
    val debugToggles = items(DEBUG_TOGGLES)
    ListPage(
        title = stringResource(R.string.options_title),
        primary = Action(stringResource(R.string.next), onClick = onNext),
        secondary = Action(stringResource(R.string.back), onClick = onBack),
    ) {
        item { SectionTitle(stringResource(R.string.graphics_display)) }
        item { BootSelections(w, bootSelections()) }
        switches(graphicsToggles)
        item {
            DrmDriver(w, R.string.drm_card, R.string.drm_card_summary, "androidboot.prefer_drm_card_name=",
                w.probe.drmDevices.sortedByDescending { it.connected }.map { it.driver })
        }
        item {
            DrmDriver(w, R.string.drm_render, R.string.drm_render_summary, "androidboot.prefer_drm_render_name=",
                w.probe.drmDevices.filter { it.render }.map { it.driver })
        }
        item { SectionTitle(stringResource(R.string.boot_options)) }
        switches(bootToggles)
        item { SerialPorts(w) }
        item { SectionTitle(stringResource(R.string.debugging)) }
        switches(debugToggles)
        item { BootSelections(w, debugSelections()) }
        // The user data beside another operating system (whole disk: on the partition sizes page)
        if (w.mode == InstallRequest.MODE_BESIDE && !w.isNtfsTarget) {
            item { SectionTitle(stringResource(R.string.layout_userdata)) }
            item {
                ToggleRow(BESIDE_USERDATA_MOUNTS, w.besideUserdataMount, { stringResource(it.label) }) {
                    w.besideUserdataMount = it
                }
            }
            item {
                Hint(stringResource(
                    if (w.besideUserdataMount == Mount.IMAGES) R.string.userdata_images_summary
                    else R.string.userdata_dirs_summary
                ))
            }
        }
        if (w.hasLinuxFirmware) {
            item { SectionTitle(stringResource(R.string.firmware)) }
            item {
                ToggleRow(listOf(false, true), w.linuxFirmware, {
                    stringResource(if (it) R.string.firmware_linux else R.string.firmware_image)
                }) { w.linuxFirmware = it }
            }
            item {
                Hint(stringResource(
                    if (w.linuxFirmware) R.string.firmware_linux_summary else R.string.firmware_image_summary
                ))
            }
        }
        if (w.mode == InstallRequest.MODE_BESIDE && w.hasUserdataFs) {
            item { SectionTitle(stringResource(R.string.userdata_fs)) }
            item { ToggleRow(Fs.entries, w.userdataFs, { it.label }) { w.userdataFs = it } }
            item { UserdataSize(w) }
        }
        if (switches.isNotEmpty()) {
            item { Spacer(Modifier.height(8.dp)) }
            switches(switches)
        }
        item { SectionTitle(stringResource(R.string.cmdline)) }
        item {
            OutlinedTextField(
                value = w.cmdline,
                onValueChange = { w.cmdline = it },
                supportingText = { Text(stringResource(R.string.cmdline_summary)) },
                textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                minLines = 3,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

//
// The kernel command line: the options edit it, and show what is in it
//

private fun Wizard.tokens() = cmdline.trim().split(Regex("\\s+")).filter(String::isNotEmpty)

private fun Wizard.hasTokens(tokens: List<String>) = tokens().containsAll(tokens)

private fun Wizard.editTokens(add: List<String>, remove: List<String>) {
    val rest = tokens().filter { it !in remove }
    cmdline = (rest + add.filter { it !in rest }).joinToString(" ")
}

/** The value of the last token with this key, like androidboot.console= */
private fun Wizard.tokenValue(key: String) = tokens().lastOrNull { it.startsWith(key) }?.removePrefix(key)

/** Replaces the tokens with this key, or removes them */
private fun Wizard.setToken(key: String, value: String?) {
    val rest = tokens().filter { !it.startsWith(key) }
    cmdline = (rest + listOfNotNull(value?.let { key + it })).joinToString(" ")
}

/** On when all the tokens are in the command line */
private data class BootToggle(val title: Int, val summary: Int, val tokens: List<String>)

private val BOOT_TOGGLES = listOf(
    BootToggle(R.string.opt_fbcon, R.string.opt_fbcon_summary, listOf("console=tty0")),
    BootToggle(R.string.opt_quiet, R.string.opt_quiet_summary, listOf("quiet")),
    BootToggle(R.string.opt_bootsplash, R.string.opt_bootsplash_summary, listOf("androidboot.bootsplash=1")),
    BootToggle(R.string.opt_virt_wifi, R.string.opt_virt_wifi_summary, listOf("androidboot.wifi_impl=virt_wifi")),
)

private val GRAPHICS_TOGGLES = listOf(
    BootToggle(R.string.opt_discrete_render, R.string.opt_discrete_render_summary,
        listOf("androidboot.prefer_discrete_render=true")),
)

/** Like the Debug entry of the live media */
private val DEBUG_TOGGLES = listOf(
    BootToggle(R.string.opt_adb, R.string.opt_adb_summary, listOf("androidboot.insecure_adb=true")),
    BootToggle(R.string.opt_early_logs, R.string.opt_early_logs_summary, listOf("androidboot.save_early_logs=1")),
    BootToggle(R.string.opt_pstore, R.string.opt_pstore_summary, listOf("efi_pstore.pstore_disable=0")),
    BootToggle(R.string.opt_console_mode, R.string.opt_console_mode_summary, listOf("androidboot.mode=console")),
)

@Composable
private fun debugSelections(): List<BootSelection> = listOf(
    BootSelection(
        stringResource(R.string.first_stage_console),
        listOf("androidboot.first_stage_console="),
        listOf(
            BootChoice(stringResource(R.string.first_stage_console_off), stringResource(R.string.first_stage_console_summary),
                emptyList()),
            BootChoice(stringResource(R.string.first_stage_console_early), stringResource(R.string.first_stage_console_early_summary),
                listOf("androidboot.first_stage_console=2")),
            BootChoice(stringResource(R.string.first_stage_console_late), stringResource(R.string.first_stage_console_late_summary),
                listOf("androidboot.first_stage_console=3")),
        ),
    ),
)

private data class BootChoice(val label: String, val summary: String, val tokens: List<String>)

/**
 * One of the choices: choosing one removes the tokens starting with the keys. The first choice,
 * without tokens, is the default.
 */
private data class BootSelection(
    val title: String,
    val keys: List<String>,
    val choices: List<BootChoice>,
    val chips: Boolean = false,
)

@Composable
private fun bootSelections(): List<BootSelection> = listOf(
    BootSelection(
        stringResource(R.string.graphics),
        listOf("androidboot.use_fb_display=", "androidboot.graphics="),
        listOf(
            BootChoice(stringResource(R.string.graphics_auto), stringResource(R.string.graphics_auto_summary), emptyList()),
            BootChoice(stringResource(R.string.graphics_fb), stringResource(R.string.graphics_fb_summary),
                listOf("androidboot.use_fb_display=true")),
            BootChoice(stringResource(R.string.graphics_swiftshader), stringResource(R.string.graphics_swiftshader_summary),
                listOf("androidboot.graphics=swiftshader")),
            BootChoice(stringResource(R.string.graphics_llvmpipe), stringResource(R.string.graphics_llvmpipe_summary),
                listOf("androidboot.graphics=llvmpipe")),
        ),
    ),
    BootSelection(
        stringResource(R.string.lcd_density),
        listOf("androidboot.lcd_density="),
        listOf(BootChoice(stringResource(R.string.lcd_density_auto), stringResource(R.string.lcd_density_summary), emptyList())) +
            listOf(160, 240, 280, 320, 400, 480).map {
                BootChoice("$it", stringResource(R.string.lcd_density_summary), listOf("androidboot.lcd_density=$it"))
            },
        chips = true,
    ),
    BootSelection(
        stringResource(R.string.fbcon_rotation),
        listOf("fbcon=rotate:"),
        listOf("0°", "90°", "180°", "270°").mapIndexed { i, label ->
            BootChoice(label, stringResource(R.string.fbcon_rotation_summary),
                if (i == 0) emptyList() else listOf("fbcon=rotate:$i"))
        },
    ),
)

@Composable
private fun BootSelections(w: Wizard, selections: List<BootSelection>) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (selection in selections) {
            val current = selection.choices.lastOrNull { it.tokens.isNotEmpty() && w.hasTokens(it.tokens) }
                ?: selection.choices.first()
            val select = { choice: BootChoice ->
                val rest = w.tokens().filter { t -> selection.keys.none { t.startsWith(it) } }
                w.cmdline = (rest + choice.tokens).joinToString(" ")
            }
            SectionTitle(selection.title)
            if (selection.chips) {
                ChipChoice(selection.choices, current, { it.label }, select)
            } else {
                ToggleRow(selection.choices, current, { it.label }, select)
            }
            Hint(current.summary)
        }
    }
}

//
// DRM drivers: the display (card) and the GPU (render) can be chosen by the name of their driver
//

/** The drivers to choose from when none is found on this computer */
private val COMMON_DRM_DRIVERS = listOf("i915", "xe", "amdgpu", "radeon", "nouveau", "virtio_gpu", "vmwgfx")

private val DRM_DRIVER_NAME = Regex("[A-Za-z0-9_-]+")

/**
 * The driver for key (androidboot.prefer_drm_card_name=...): automatic (none), one of the found
 * ones (common ones if none), or one written by hand
 */
@Composable
private fun DrmDriver(w: Wizard, title: Int, summary: Int, key: String, found: List<String>) {
    val current = w.tokenValue(key)
    val drivers = found.distinct().ifEmpty { COMMON_DRM_DRIVERS }
    var other by remember { mutableStateOf(false) }
    var otherText by remember { mutableStateOf("") }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(Modifier.padding(horizontal = 4.dp)) {
            Text(stringResource(title), style = MaterialTheme.typography.titleMedium)
            Text(
                stringResource(summary),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            item {
                FilterChip(
                    selected = !other && current == null,
                    onClick = { other = false; w.setToken(key, null) },
                    label = { Text(stringResource(R.string.graphics_auto)) },
                )
            }
            items(drivers.size) { i ->
                FilterChip(
                    selected = !other && current == drivers[i],
                    onClick = { other = false; w.setToken(key, drivers[i]) },
                    label = { Text(drivers[i]) },
                )
            }
            item {
                FilterChip(
                    selected = other || (current != null && current !in drivers),
                    onClick = {
                        other = true
                        otherText = current.orEmpty()
                    },
                    label = { Text(stringResource(R.string.serial_other)) },
                )
            }
        }
        if (other || (current != null && current !in drivers)) {
            OutlinedTextField(
                value = if (other) otherText else current.orEmpty(),
                onValueChange = { v ->
                    otherText = v.trim()
                    if (otherText.matches(DRM_DRIVER_NAME)) w.setToken(key, otherText)
                    else if (otherText.isEmpty()) w.setToken(key, null)
                },
                label = { Text(stringResource(R.string.drm_driver_name)) },
                isError = otherText.isNotEmpty() && !otherText.matches(DRM_DRIVER_NAME),
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

//
// Serial ports: each use (kernel messages, Android shell, logcat) takes a port of its own, or none
//

/** A serial port or a virtio console (hvc0...), not a virtual terminal (tty0...) nor ttynull */
private fun isSerialPort(name: String) = when {
    name.startsWith("hvc") -> name.length > 3 && name.drop(3).all(Char::isDigit)
    name.startsWith("tty") -> name != "ttynull" && !name.drop(3).all(Char::isDigit)
    else -> false
}

/** The port of a console= token of a serial port, without options like ,115200 */
private fun serialConsolePort(token: String) = token.takeIf { it.startsWith("console=") }
    ?.removePrefix("console=")?.substringBefore(',')?.takeIf { isSerialPort(it) }

/** The serial port of the kernel console; console=tty0 is the framebuffer console */
private fun Wizard.kernelSerialPort() = tokens().mapNotNull { serialConsolePort(it) }.lastOrNull()

private fun Wizard.setKernelSerialPort(port: String?) {
    if (port == kernelSerialPort()) return
    val rest = tokens().filter {
        // 8250.nr_uarts=1 only registers ttyS0
        serialConsolePort(it) == null && !(it == "8250.nr_uarts=1" && port != "ttyS0")
    }
    cmdline = (rest + listOfNotNull(port?.let { "console=$it" })).joinToString(" ")
}

private fun Wizard.setLogcatPort(port: String?) {
    setToken("androidboot.seriallogging=", port)
    if (port == null) setToken("androidboot.seriallogging.logcat_buffer=", null)
}

@Composable
private fun SerialPorts(w: Wizard) {
    val detected = w.probe.serialPorts.toList()
    val kernel = w.kernelSerialPort()
    val shell = w.tokenValue("androidboot.console=")
    val logcat = w.tokenValue("androidboot.seriallogging=")
    // Found ones, and the ones the command line already uses
    val ports = (detected + listOfNotNull(kernel, shell, logcat).filter { isSerialPort(it) }).distinct()
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Column {
            SectionTitle(stringResource(R.string.serial_ports))
            Hint(
                if (detected.isEmpty()) stringResource(R.string.serial_none_found)
                else stringResource(R.string.serial_found, detected.joinToString(", "))
            )
        }
        SerialUse(R.string.serial_kernel, R.string.serial_kernel_summary, kernel, ports) { w.setKernelSerialPort(it) }
        SerialUse(
            R.string.android_console, R.string.android_console_summary, shell, ports,
            extra = listOf(stringResource(R.string.android_console_screen) to "tty0"),
            off = R.string.android_console_default,
        ) { w.setToken("androidboot.console=", it) }
        SerialUse(R.string.logcat_serial, R.string.logcat_summary, logcat, ports) { w.setLogcatPort(it) }
        if (logcat != null) {
            val buffers = listOf(
                R.string.logcat_crash to "crash", R.string.logcat_default to "default", R.string.logcat_all to "all",
            )
            val buffer = w.tokenValue("androidboot.seriallogging.logcat_buffer=") ?: "crash"
            ToggleRow(buffers, buffers.firstOrNull { it.second == buffer } ?: buffers.first(),
                { stringResource(it.first) }) { w.setToken("androidboot.seriallogging.logcat_buffer=", it.second) }
        }
    }
}

/** One use of a serial port: off (null), one of extra (label to value), a port, or one written by hand */
@Composable
private fun SerialUse(
    title: Int,
    summary: Int,
    current: String?,
    ports: List<String>,
    extra: List<Pair<String, String>> = emptyList(),
    off: Int = R.string.serial_off,
    onSelect: (String?) -> Unit,
) {
    var other by remember { mutableStateOf(false) }
    var otherText by remember { mutableStateOf("") }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(Modifier.padding(horizontal = 4.dp)) {
            Text(stringResource(title), style = MaterialTheme.typography.titleMedium)
            Text(
                stringResource(summary),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            item {
                FilterChip(
                    selected = !other && current == null,
                    onClick = { other = false; onSelect(null) },
                    label = { Text(stringResource(off)) },
                )
            }
            items(extra.size + ports.size) { i ->
                val (label, value) = extra.getOrNull(i) ?: (ports[i - extra.size] to ports[i - extra.size])
                FilterChip(
                    selected = !other && current == value,
                    onClick = { other = false; onSelect(value) },
                    label = { Text(label) },
                )
            }
            item {
                FilterChip(
                    selected = other,
                    onClick = {
                        other = true
                        otherText = current?.takeIf { isSerialPort(it) }.orEmpty()
                    },
                    label = { Text(stringResource(R.string.serial_other)) },
                )
            }
        }
        if (other) {
            OutlinedTextField(
                value = otherText,
                onValueChange = { v ->
                    otherText = v.trim()
                    if (isSerialPort(otherText)) onSelect(otherText)
                },
                label = { Text(stringResource(R.string.serial_port_name)) },
                supportingText = { Text(stringResource(R.string.serial_port_hint)) },
                isError = otherText.isNotEmpty() && !isSerialPort(otherText),
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}
