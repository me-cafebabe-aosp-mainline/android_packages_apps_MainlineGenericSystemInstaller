/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)

package device.mainline.generic.installer

import android.os.Bundle
import android.os.PowerManager
import android.text.format.Formatter
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Album
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.InstallDesktop
import androidx.compose.material.icons.outlined.Save
import androidx.compose.material.icons.outlined.SdCard
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.SystemUpdate
import androidx.compose.material.icons.outlined.Usb
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeFlexibleTopAppBar
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedListItem
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.ToggleButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.toShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.Executors

private enum class Screen { LOADING, MODES, TARGETS, PARTITIONS, OPTIONS, CONFIRM, PROGRESS, DONE, FAILED }

/** Like the scripts: room for user data, partition table and BIOS boot partition */
private const val USERDATA_MIN_MIB = 4096L
private const val OVERHEAD_MIB = 4L

private data class Action(val label: String, val enabled: Boolean = true, val onClick: () -> Unit)

private data class Choice(
    val id: String,
    val icon: ImageVector,
    val title: String,
    val summary: String,
    val enabled: Boolean,
)

/** Choose what to do, where, with which options, confirm, install. */
class MainActivity : ComponentActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private var installer: ISystemInstaller? = null
    private var probe: ProbeResult? = null

    private var screen by mutableStateOf(Screen.LOADING)
    private var message by mutableStateOf("")
    private var mode by mutableIntStateOf(InstallRequest.MODE_DISK)
    private var target by mutableStateOf("")
    private var cmdline by mutableStateOf("")
    private var userdataGiB by mutableStateOf("16")
    private var bootEntries by mutableStateOf(true)
    private var allowDowngrade by mutableStateOf(false)
    private var userdataFs by mutableStateOf("ext4")
    /** For the serial options; changing it renames the port in the command line */
    private var serialPort by mutableStateOf("")
    /** Partition sizes in MiB, as typed, for the disk in sizesTarget */
    private val sizes = mutableStateMapOf<String, String>()
    private var sizesTarget = ""
    private var confirmText by mutableStateOf("")
    private var progress by mutableFloatStateOf(0f)
    private var step by mutableStateOf("")
    private var destructive by mutableStateOf(false)
    private val log = mutableStateListOf<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { InstallerTheme { App() } }
        executor.execute { load() }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }

    private fun load() {
        val result = runCatching {
            val service = Installer.get() ?: error("systeminstallerd")
            check(!service.isRunning) { getString(R.string.running) }
            service to service.probe()
        }
        runOnUiThread {
            result.onSuccess { (service, probe) ->
                installer = service
                this.probe = probe
                cmdline = probe.system.defaultCmdline
                serialPort = detectSerialPort(probe.system.arch)
                screen = Screen.MODES
            }.onFailure {
                message = getString(R.string.unavailable, it.message)
                screen = Screen.FAILED
            }
        }
    }

    private fun start() {
        val p = probe ?: return
        val request = InstallRequest().also {
            it.mode = mode
            it.target = target
            it.userdataSizeMiB = (userdataGiB.toIntOrNull() ?: 16).coerceAtLeast(4) * 1024
            // Strings must not be null: the daemon side is not nullable
            it.cmdline = if (cmdline.trim() == p.system.defaultCmdline) "" else cmdline.trim()
            it.bootEntries = bootEntries
            it.allowDowngrade = allowDowngrade
            it.userdataFs = userdataFs
            it.sizes = if (mode == InstallRequest.MODE_DISK) {
                p.layout.mapNotNull { l ->
                    sizes[l.name]?.toIntOrNull()?.takeIf { v -> v != l.defaultMiB }?.let { v ->
                        PartitionSize().apply {
                            name = l.name
                            sizeMiB = v
                        }
                    }
                }.toTypedArray()
            } else {
                emptyArray()
            }
        }
        progress = 0f
        step = ""
        destructive = false
        log.clear()
        screen = Screen.PROGRESS

        val callback = object : IProgressCallback.Stub() {
            override fun onProgress(percent: Int, text: String) = runOnUiThread {
                progress = percent / 100f
                step = text
            }

            override fun onLog(line: String) = runOnUiThread { log += line }

            override fun onDestructive() = runOnUiThread { destructive = true }

            override fun onFinished(success: Boolean, error: String) = runOnUiThread {
                message = error
                screen = if (success) Screen.DONE else Screen.FAILED
            }
        }
        executor.execute {
            runCatching { installer!!.start(request, callback) }.onFailure {
                runOnUiThread {
                    message = it.message ?: it.toString()
                    screen = Screen.FAILED
                }
            }
        }
    }

    private fun back() {
        screen = when (screen) {
            Screen.TARGETS -> Screen.MODES
            Screen.PARTITIONS -> Screen.TARGETS
            Screen.OPTIONS -> if (mode == InstallRequest.MODE_DISK) Screen.PARTITIONS else Screen.TARGETS
            Screen.CONFIRM -> Screen.OPTIONS
            else -> {
                finish()
                screen
            }
        }
    }

    //
    // Screens
    //

    @Composable
    private fun App() {
        BackHandler(enabled = screen != Screen.PROGRESS) { back() }
        BackHandler(enabled = screen == Screen.PROGRESS) {}
        // The background and content color of every screen, also of the
        // ones without a Scaffold and during transitions
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Screens()
        }
    }

    @Composable
    private fun Screens() {
        AnimatedContent(targetState = screen, label = "screen") {
            when (it) {
                Screen.LOADING -> Loading()
                Screen.MODES -> Modes()
                Screen.TARGETS -> Targets()
                Screen.PARTITIONS -> Partitions()
                Screen.OPTIONS -> Options()
                Screen.CONFIRM -> Confirm()
                Screen.PROGRESS -> Progress()
                Screen.DONE, Screen.FAILED -> Result(it == Screen.DONE)
            }
        }
    }

    @Composable
    private fun Loading() {
        Centered {
            LoadingIndicator(Modifier.size(96.dp))
            Spacer(Modifier.height(24.dp))
            Text(stringResource(R.string.loading), style = MaterialTheme.typography.titleMedium)
        }
    }

    @Composable
    private fun Modes() {
        val p = probe ?: return
        val s = p.system
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
            primary = Action(stringResource(R.string.next), s.sourceFound) { screen = Screen.TARGETS },
            secondary = Action(stringResource(R.string.close)) { finish() },
        ) {
            if (s.secureBoot == 1) item { Notice(stringResource(R.string.secure_boot_on)) }
            if (!s.sourceFound) item { Notice(stringResource(R.string.no_source, s.sourceMessage)) }
            item { SectionTitle(stringResource(R.string.mode_title)) }
            choices(modes, "$mode") { mode = it.toInt() }
        }
    }

    private fun targetChoices(p: ProbeResult, context: android.content.Context): List<Choice> {
        fun size(bytes: Long) = Formatter.formatFileSize(context, bytes)
        fun reason(usable: Boolean, reason: String) = if (usable) "" else reason
        return when (mode) {
            InstallRequest.MODE_DISK -> p.disks.map {
                Choice(
                    it.name,
                    when (it.type) {
                        "usb" -> Icons.Outlined.Usb
                        "sd" -> Icons.Outlined.SdCard
                        else -> Icons.Outlined.Storage
                    },
                    "${context.getString(diskType(it.type))} · ${size(it.sizeBytes)}",
                    listOf(
                        listOf(it.model, it.name).filter(String::isNotEmpty).joinToString(" · "),
                        reason(it.usable, it.reason),
                    ).filter(String::isNotEmpty).joinToString("\n"),
                    it.usable,
                )
            }
            InstallRequest.MODE_BESIDE -> p.partitions.map {
                val free = if (it.freeMiB < 0) "?" else size(it.freeMiB * 1048576)
                Choice(
                    it.name,
                    when {
                        it.fsType == "iso9660" || it.fsType == "udf" -> Icons.Outlined.Album
                        it.os.isNotEmpty() -> Icons.Outlined.Computer
                        else -> Icons.Outlined.Storage
                    },
                    "${it.name} · ${it.fsType.uppercase().ifEmpty { "?" }} · ${size(it.sizeBytes)}",
                    listOf(
                        it.os.ifEmpty { it.label },
                        context.getString(R.string.free, free),
                        reason(it.usable, it.reason),
                    ).filter(String::isNotEmpty).joinToString("\n"),
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
                    listOf(context.getString(R.string.built, date(it.buildDateUtc)), reason(it.upgradable, it.reason))
                        .filter(String::isNotEmpty).joinToString("\n"),
                    it.upgradable,
                )
            }
        }
    }

    private fun diskType(type: String) = when (type) {
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

    @Composable
    private fun Targets() {
        val p = probe ?: return
        val list = targetChoices(p, LocalContext.current)
        if (list.none { it.id == target && it.enabled }) target = ""
        val title = when (mode) {
            InstallRequest.MODE_DISK -> R.string.target_disk
            InstallRequest.MODE_BESIDE -> R.string.target_beside
            else -> R.string.target_upgrade
        }
        ListPage(
            title = stringResource(title),
            primary = Action(stringResource(R.string.next), target.isNotEmpty()) {
                if (mode == InstallRequest.MODE_DISK) {
                    if (sizesTarget != target) {
                        sizes.clear()
                        sizesTarget = target
                    }
                    screen = Screen.PARTITIONS
                } else {
                    screen = Screen.OPTIONS
                }
            },
            secondary = Action(stringResource(R.string.back)) { back() },
        ) {
            if (list.isEmpty()) {
                item { Text(stringResource(R.string.target_none), style = MaterialTheme.typography.bodyLarge) }
            } else {
                choices(list, target) { target = it }
            }
        }
    }

    @Composable
    private fun Partitions() {
        val p = probe ?: return
        val context = LocalContext.current
        fun size(mib: Long) = Formatter.formatFileSize(context, mib * 1048576)
        val disk = p.disks.firstOrNull { it.name == target } ?: return
        val diskMiB = disk.sizeBytes / 1048576
        val parts = p.layout.toList()
        val values = parts.map { (sizes[it.name] ?: "${it.defaultMiB}").toLongOrNull() ?: 0L }
        val invalid = parts.indices.any { values[it] < parts[it].minimumMiB }
        val userdataMiB = diskMiB - OVERHEAD_MIB - values.sum()
        val colors = MaterialTheme.colorScheme.let {
            listOf(it.primary, it.secondary, it.tertiary, it.error, it.primaryContainer, it.tertiaryContainer)
        }
        fun color(i: Int) = colors[i % colors.size]
        val userdataColor = MaterialTheme.colorScheme.surfaceVariant

        ListPage(
            title = stringResource(R.string.partitions_title),
            subtitle = "${disk.name} · ${size(diskMiB)}",
            primary = Action(stringResource(R.string.next), !invalid && userdataMiB >= USERDATA_MIN_MIB) {
                screen = Screen.OPTIONS
            },
            secondary = Action(stringResource(R.string.back)) { back() },
        ) {
            item {
                UsageBar(values.indices.map { values[it] to color(it) } + (userdataMiB to userdataColor))
            }
            item {
                Row(
                    Modifier.padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Dot(userdataColor)
                    Text(
                        if (userdataMiB >= USERDATA_MIN_MIB) {
                            stringResource(R.string.userdata_rest, size(userdataMiB))
                        } else {
                            stringResource(R.string.userdata_too_small, size(USERDATA_MIN_MIB))
                        },
                        style = MaterialTheme.typography.bodyLarge,
                        color = if (userdataMiB >= USERDATA_MIN_MIB) Color.Unspecified
                                else MaterialTheme.colorScheme.error,
                    )
                }
            }
            itemsIndexed(parts) { i, part ->
                OutlinedTextField(
                    value = sizes[part.name] ?: "${part.defaultMiB}",
                    onValueChange = { v -> sizes[part.name] = v.filter(Char::isDigit).take(9) },
                    label = { Text(part.name) },
                    leadingIcon = { Dot(color(i)) },
                    suffix = { Text("MiB") },
                    supportingText = {
                        Text(stringResource(
                            R.string.partition_size_hint,
                            size(part.minimumMiB.toLong()), size(part.defaultMiB.toLong()),
                        ))
                    },
                    isError = values[i] < part.minimumMiB,
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            item {
                TextButton(onClick = { sizes.clear() }, enabled = sizes.isNotEmpty()) {
                    Text(stringResource(R.string.reset_sizes))
                }
            }
        }
    }

    /** How a disk is shared, each part at least a sliver */
    @Composable
    private fun UsageBar(parts: List<Pair<Long, Color>>) {
        val total = parts.sumOf { maxOf(it.first, 0L) }.coerceAtLeast(1L)
        Row(
            Modifier.fillMaxWidth().height(32.dp).clip(RoundedCornerShape(16.dp)),
            horizontalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            parts.filter { it.first > 0 }.forEach { (mib, color) ->
                Box(
                    Modifier.weight(maxOf(mib.toFloat() / total, 0.015f))
                        .fillMaxHeight()
                        .background(color)
                )
            }
        }
    }

    @Composable
    private fun Dot(color: Color) {
        Box(Modifier.size(12.dp).clip(CircleShape).background(color))
    }

    private fun isNtfsTarget() = mode == InstallRequest.MODE_BESIDE &&
        probe?.partitions?.any { it.name == target && it.fsType == "ntfs" } == true

    /** Whether userdata gets a filesystem of its own: a partition, or an image on NTFS */
    private fun hasUserdataFs() = mode == InstallRequest.MODE_DISK || isNtfsTarget()

    private fun hasBootEntries() = when (mode) {
        InstallRequest.MODE_BESIDE -> true
        InstallRequest.MODE_UPGRADE ->
            probe?.installations?.any { it.id == target && it.kind == Installation.KIND_BESIDE } == true
        else -> false
    }

    @Composable
    private fun Options() {
        val switches = buildList {
            if (hasBootEntries()) add(Triple(R.string.boot_entries, R.string.boot_entries_summary, 0))
            if (mode == InstallRequest.MODE_UPGRADE) {
                add(Triple(R.string.allow_downgrade, R.string.allow_downgrade_summary, 1))
            }
        }
        ListPage(
            title = stringResource(R.string.options_title),
            primary = Action(stringResource(R.string.next)) {
                confirmText = ""
                screen = Screen.CONFIRM
            },
            secondary = Action(stringResource(R.string.back)) { back() },
        ) {
            bootOptions()
            if (hasUserdataFs()) {
                item { SectionTitle(stringResource(R.string.userdata_fs)) }
                item {
                    val choices = listOf("ext4", "f2fs")
                    Row(horizontalArrangement = Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween)) {
                        choices.forEachIndexed { i, fs ->
                            ToggleButton(
                                checked = userdataFs == fs,
                                onCheckedChange = { userdataFs = fs },
                                shapes = if (i == 0) ButtonGroupDefaults.connectedLeadingButtonShapes()
                                         else ButtonGroupDefaults.connectedTrailingButtonShapes(),
                                modifier = Modifier.weight(1f),
                            ) { Text(fs.uppercase()) }
                        }
                    }
                }
            }
            if (isNtfsTarget()) {
                item {
                    OutlinedTextField(
                        value = userdataGiB,
                        onValueChange = { v -> userdataGiB = v.filter(Char::isDigit) },
                        label = { Text(stringResource(R.string.userdata_size)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
            if (switches.isNotEmpty()) item { Spacer(Modifier.height(8.dp)) }
            itemsIndexed(switches) { index, (title, summary, which) ->
                val checked = if (which == 0) bootEntries else allowDowngrade
                val toggle: () -> Unit = {
                    if (which == 0) bootEntries = !bootEntries else allowDowngrade = !allowDowngrade
                }
                SegmentedListItem(
                    onClick = toggle,
                    shapes = ListItemDefaults.segmentedShapes(index, switches.size),
                    supportingContent = { Text(stringResource(summary)) },
                    trailingContent = { Switch(checked = checked, onCheckedChange = null) },
                ) { Text(stringResource(title)) }
            }
            item { SectionTitle(stringResource(R.string.cmdline)) }
            item {
                OutlinedTextField(
                    value = cmdline,
                    onValueChange = { cmdline = it },
                    supportingText = { Text(stringResource(R.string.cmdline_summary)) },
                    textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    minLines = 3,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }

    //
    // Boot options: they edit the kernel command line, and show what is in it
    //

    private fun cmdlineTokens() = cmdline.trim().split(Regex("\\s+")).filter(String::isNotEmpty)

    private fun hasTokens(tokens: List<String>) = cmdlineTokens().containsAll(tokens)

    private fun editTokens(add: List<String>, remove: List<String>) {
        val rest = cmdlineTokens().filter { it !in remove }
        cmdline = (rest + add.filter { it !in rest }).joinToString(" ")
    }

    private data class BootToggle(
        val title: Int,
        val summary: Int,
        val isOn: () -> Boolean,
        val set: (Boolean) -> Unit,
    )

    /** On or off: the tokens are in the command line, or not */
    private fun tokenToggle(title: Int, summary: Int, tokens: List<String>) = BootToggle(
        title, summary, { hasTokens(tokens) },
        { on -> if (on) editTokens(tokens, emptyList()) else editTokens(emptyList(), tokens) },
    )

    private data class BootChoice(val label: String, val summary: String?, val tokens: List<String>)

    /**
     * One of the choices: setting one removes the tokens starting with the
     * keys. The first choice, without tokens, is the default.
     */
    private data class BootSelection(
        val title: String,
        val keys: List<String>,
        val choices: List<BootChoice>,
        val chips: Boolean = false,
    )

    //
    // Serial port
    //

    private fun detectedSerialPorts() = probe?.serialPorts?.toList().orEmpty()

    /**
     * A serial port or a virtio console (hvc0...), not a virtual terminal
     * (tty0, tty1...) nor ttynull
     */
    private fun isSerialPort(name: String) = when {
        name.startsWith("hvc") -> name.length > 3 && name.drop(3).all(Char::isDigit)
        name.startsWith("tty") -> name != "ttynull" && !name.drop(3).all(Char::isDigit)
        else -> false
    }

    private fun detectSerialPort(arch: String): String {
        val tokens = cmdlineTokens()
        fun value(key: String) = tokens.filter { it.startsWith(key) }
            .map { it.removePrefix(key).substringBefore(',') }.lastOrNull { isSerialPort(it) }
        return value("console=") ?: value("androidboot.seriallogging=") ?: value("androidboot.console=")
            ?: detectedSerialPorts().firstOrNull() ?: if (arch == "x86_64") "ttyS0" else "ttyAMA0"
    }

    private fun isConsole(token: String, port: String) =
        token == "console=$port" || token.startsWith("console=$port,")

    private fun setSerialPort(port: String) {
        val old = serialPort
        serialPort = port
        if (!isSerialPort(port) || port == old) return
        cmdline = cmdlineTokens().mapNotNull {
            when {
                isConsole(it, old) -> "console=$port" + it.removePrefix("console=$old")
                it == "androidboot.seriallogging=$old" -> "androidboot.seriallogging=$port"
                it == "androidboot.console=$old" -> "androidboot.console=$port"
                // Only ttyS0 is registered with it
                it == "8250.nr_uarts=1" && port != "ttyS0" -> null
                else -> it
            }
        }.joinToString(" ")
    }

    private fun serialConsoleToggle() = BootToggle(
        R.string.opt_serial, R.string.opt_serial_summary,
        { cmdlineTokens().any { isConsole(it, serialPort) } },
        { on ->
            val rest = cmdlineTokens().filter { !isConsole(it, serialPort) && it != "8250.nr_uarts=1" }
            cmdline = (rest + if (on) listOf("console=$serialPort") else emptyList()).joinToString(" ")
        },
    )

    private fun bootToggles() = listOf(
        tokenToggle(R.string.opt_fbcon, R.string.opt_fbcon_summary, listOf("console=tty0")),
        serialConsoleToggle(),
        tokenToggle(R.string.opt_quiet, R.string.opt_quiet_summary, listOf("quiet")),
        tokenToggle(R.string.opt_bootsplash, R.string.opt_bootsplash_summary, listOf("androidboot.bootsplash=1")),
        tokenToggle(R.string.opt_adb, R.string.opt_adb_summary, listOf("androidboot.insecure_adb=true")),
        tokenToggle(R.string.opt_early_logs, R.string.opt_early_logs_summary, listOf("androidboot.save_early_logs=1")),
        tokenToggle(R.string.opt_virt_wifi, R.string.opt_virt_wifi_summary, listOf("androidboot.wifi_impl=virt_wifi")),
    )

    @Composable
    private fun bootSelections(): List<BootSelection> = buildList {
        add(BootSelection(
            stringResource(R.string.graphics),
            listOf("androidboot.use_fb_display=", "androidboot.graphics="),
            listOf(
                BootChoice(stringResource(R.string.graphics_auto), stringResource(R.string.graphics_auto_summary), emptyList()),
                BootChoice(stringResource(R.string.graphics_fb), stringResource(R.string.graphics_fb_summary),
                    listOf("androidboot.use_fb_display=true")),
                BootChoice(stringResource(R.string.graphics_swiftshader), stringResource(R.string.graphics_swiftshader_summary),
                    listOf("androidboot.graphics=swiftshader")),
            ),
        ))
        add(BootSelection(
            stringResource(R.string.lcd_density),
            listOf("androidboot.lcd_density="),
            listOf(BootChoice(stringResource(R.string.lcd_density_auto), stringResource(R.string.lcd_density_summary), emptyList())) +
                listOf(160, 240, 280, 320, 400, 480).map {
                    BootChoice("$it", stringResource(R.string.lcd_density_summary), listOf("androidboot.lcd_density=$it"))
                },
            chips = true,
        ))
        add(BootSelection(
            stringResource(R.string.fbcon_rotation),
            listOf("fbcon=rotate:"),
            listOf("0°", "90°", "180°", "270°").mapIndexed { i, label ->
                BootChoice(label, stringResource(R.string.fbcon_rotation_summary),
                    if (i == 0) emptyList() else listOf("fbcon=rotate:$i"))
            },
        ))
        add(BootSelection(
            stringResource(R.string.android_console),
            listOf("androidboot.console="),
            listOf(
                BootChoice(stringResource(R.string.android_console_default),
                    stringResource(R.string.android_console_default_summary), emptyList()),
                BootChoice(stringResource(R.string.android_console_screen),
                    stringResource(R.string.android_console_screen_summary), listOf("androidboot.console=tty0")),
                BootChoice(serialPort, stringResource(R.string.android_console_serial_summary),
                    listOf("androidboot.console=$serialPort")),
            ),
        ))
        val logcat = listOf("androidboot.seriallogging=$serialPort")
        add(BootSelection(
            stringResource(R.string.logcat_serial),
            listOf("androidboot.seriallogging=", "androidboot.seriallogging.logcat_buffer="),
            listOf(
                BootChoice(stringResource(R.string.logcat_off), stringResource(R.string.logcat_summary), emptyList()),
                BootChoice(stringResource(R.string.logcat_crash), stringResource(R.string.logcat_summary),
                    logcat + "androidboot.seriallogging.logcat_buffer=crash"),
                BootChoice(stringResource(R.string.logcat_default), stringResource(R.string.logcat_summary),
                    logcat + "androidboot.seriallogging.logcat_buffer=default"),
                BootChoice(stringResource(R.string.logcat_all), stringResource(R.string.logcat_summary),
                    logcat + "androidboot.seriallogging.logcat_buffer=all"),
            ),
        ))
    }

    private fun select(selection: BootSelection, choice: BootChoice) {
        val rest = cmdlineTokens().filter { t -> selection.keys.none { t.startsWith(it) } }
        cmdline = (rest + choice.tokens).joinToString(" ")
    }

    private fun selected(selection: BootSelection) =
        selection.choices.lastOrNull { it.tokens.isNotEmpty() && hasTokens(it.tokens) } ?: selection.choices.first()

    private fun LazyListScope.bootOptions() {
        item { SerialPort() }
        item { BootSelections() }
        item { SectionTitle(stringResource(R.string.boot_options)) }
        val toggles = bootToggles()
        itemsIndexed(toggles) { index, toggle ->
            val checked = toggle.isOn()
            SegmentedListItem(
                onClick = { toggle.set(!checked) },
                shapes = ListItemDefaults.segmentedShapes(index, toggles.size),
                supportingContent = { Text(stringResource(toggle.summary)) },
                trailingContent = { Switch(checked = checked, onCheckedChange = null) },
            ) { Text(stringResource(toggle.title)) }
        }
    }

    @Composable
    private fun SerialPort() {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionTitle(stringResource(R.string.serial_port))
            OutlinedTextField(
                value = serialPort,
                onValueChange = { setSerialPort(it.trim()) },
                supportingText = { Text(stringResource(R.string.serial_port_summary)) },
                isError = !isSerialPort(serialPort),
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth(),
            )
            val detected = detectedSerialPorts()
            if (detected.isNotEmpty()) {
                Text(
                    stringResource(R.string.serial_port_detected),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 4.dp),
                )
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(detected.size) { i ->
                        val port = detected[i]
                        FilterChip(
                            selected = port == serialPort,
                            onClick = { setSerialPort(port) },
                            label = { Text(port) },
                        )
                    }
                }
            }
        }
    }

    @Composable
    private fun BootSelections() {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (selection in bootSelections()) {
                val current = selected(selection)
                SectionTitle(selection.title)
                if (selection.chips) {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(selection.choices.size) { i ->
                            val choice = selection.choices[i]
                            FilterChip(
                                selected = choice == current,
                                onClick = { select(selection, choice) },
                                label = { Text(choice.label) },
                            )
                        }
                    }
                } else {
                    Row(horizontalArrangement = Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween)) {
                        selection.choices.forEachIndexed { i, choice ->
                            ToggleButton(
                                checked = choice == current,
                                onCheckedChange = { select(selection, choice) },
                                shapes = when (i) {
                                    0 -> ButtonGroupDefaults.connectedLeadingButtonShapes()
                                    selection.choices.lastIndex -> ButtonGroupDefaults.connectedTrailingButtonShapes()
                                    else -> ButtonGroupDefaults.connectedMiddleButtonShapes()
                                },
                                modifier = Modifier.weight(1f),
                            ) { Text(choice.label, maxLines = 1) }
                        }
                    }
                }
                current.summary?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 4.dp),
                    )
                }
            }
        }
    }

    @Composable
    private fun Confirm() {
        val p = probe ?: return
        val title = p.system.title
        val disk = mode == InstallRequest.MODE_DISK
        ListPage(
            title = stringResource(R.string.confirm_title),
            primary = Action(stringResource(R.string.install), !disk || confirmText == target) { start() },
            secondary = Action(stringResource(R.string.back)) { back() },
        ) {
            item {
                when (mode) {
                    InstallRequest.MODE_DISK -> {
                        val disk = p.disks.firstOrNull { it.name == target }
                        val what = listOfNotNull(
                            disk?.let { stringResource(diskType(it.type)) },
                            disk?.model?.takeIf { it.isNotEmpty() },
                            Formatter.formatFileSize(LocalContext.current, disk?.sizeBytes ?: 0),
                        ).joinToString(" · ")
                        Notice(stringResource(R.string.confirm_disk, target, what))
                    }
                    InstallRequest.MODE_BESIDE -> Summary(stringResource(R.string.confirm_beside, title, target))
                    else -> Summary(stringResource(R.string.confirm_upgrade, target, title))
                }
            }
            if (disk) {
                item {
                    OutlinedTextField(
                        value = confirmText,
                        onValueChange = { confirmText = it.trim() },
                        label = { Text(stringResource(R.string.confirm_type, target)) },
                        singleLine = true,
                        isError = confirmText.isNotEmpty() && confirmText != target,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }
    }

    @Composable
    private fun Progress() {
        val animated by animateFloatAsState(
            progress, MaterialTheme.motionScheme.slowSpatialSpec<Float>(), label = "progress",
        )
        val logState = rememberLazyListState()
        LaunchedEffect(log.size) { if (log.isNotEmpty()) logState.animateScrollToItem(log.lastIndex) }
        Page(
            title = stringResource(R.string.progress_title),
            subtitle = step.ifEmpty { null },
            primary = null,
            secondary = Action(stringResource(R.string.cancel), !destructive) {
                destructive = true
                executor.execute { runCatching { installer?.cancel() } }
            },
        ) { padding ->
            Column(
                Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                LinearWavyProgressIndicator(progress = { animated }, modifier = Modifier.fillMaxWidth())
                Text("${(progress * 100).toInt()} %", style = MaterialTheme.typography.labelLarge)
                OutlinedCard(Modifier.fillMaxWidth().weight(1f)) { Log(logState) }
            }
        }
    }

    private fun logText() = buildString {
        if (screen == Screen.FAILED && message.isNotEmpty()) append(message).append("\n\n")
        log.forEach { append(it).append('\n') }
    }

    @Composable
    private fun Result(success: Boolean) {
        val saveLog = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/plain")) { uri ->
            if (uri != null) {
                val text = logText()
                executor.execute {
                    runCatching { contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray()) } }
                }
            }
        }
        Page(
            title = "",
            primary = if (success) {
                Action(stringResource(R.string.restart)) { getSystemService(PowerManager::class.java).reboot(null) }
            } else {
                null
            },
            secondary = Action(stringResource(R.string.close)) { finish() },
        ) { padding ->
            Column(
                Modifier.fillMaxSize().padding(padding).padding(horizontal = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Spacer(Modifier.height(16.dp))
                Box(
                    Modifier.size(120.dp)
                        .clip(MaterialShapes.Cookie12Sided.toShape())
                        .background(
                            if (success) MaterialTheme.colorScheme.primaryContainer
                            else MaterialTheme.colorScheme.errorContainer
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        if (success) Icons.Outlined.CheckCircle else Icons.Outlined.ErrorOutline,
                        contentDescription = null,
                        modifier = Modifier.size(56.dp),
                        tint = if (success) MaterialTheme.colorScheme.onPrimaryContainer
                               else MaterialTheme.colorScheme.onErrorContainer,
                    )
                }
                Text(
                    stringResource(if (success) R.string.done_title else R.string.failed_title),
                    style = MaterialTheme.typography.headlineMedium,
                    textAlign = TextAlign.Center,
                )
                SelectionContainer {
                    Text(
                        if (success) stringResource(R.string.done_message) else message,
                        style = MaterialTheme.typography.bodyLarge,
                        textAlign = TextAlign.Center,
                    )
                }
                if (log.isNotEmpty()) {
                    FilledTonalButton(
                        onClick = { saveLog.launch("installer.log") },
                        shapes = ButtonDefaults.shapes(),
                    ) {
                        Icon(Icons.Outlined.Save, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.save_log))
                    }
                }
                if (!success && log.isNotEmpty()) {
                    OutlinedCard(Modifier.fillMaxWidth().weight(1f)) { Log(rememberLazyListState()) }
                }
            }
        }
    }

    //
    // Building blocks
    //

    @Composable
    private fun Page(
        title: String,
        subtitle: String? = null,
        primary: Action?,
        secondary: Action?,
        content: @Composable (PaddingValues) -> Unit,
    ) {
        val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
        Scaffold(
            modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
            topBar = {
                LargeFlexibleTopAppBar(
                    title = { Text(title) },
                    subtitle = if (subtitle != null) {
                        { Text(subtitle, maxLines = 2) }
                    } else {
                        null
                    },
                    scrollBehavior = scrollBehavior,
                )
            },
            bottomBar = {
                Row(
                    Modifier.fillMaxWidth()
                        .windowInsetsPadding(WindowInsets.navigationBars)
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
                ) {
                    secondary?.let { TextButton(onClick = it.onClick, enabled = it.enabled) { Text(it.label) } }
                    primary?.let {
                        Button(onClick = it.onClick, shapes = ButtonDefaults.shapes(), enabled = it.enabled) {
                            Text(it.label)
                        }
                    }
                }
            },
            content = content,
        )
    }

    @Composable
    private fun ListPage(
        title: String,
        subtitle: String? = null,
        primary: Action?,
        secondary: Action?,
        content: LazyListScope.() -> Unit,
    ) {
        Page(title, subtitle, primary, secondary) { padding ->
            LazyColumn(
                contentPadding = PaddingValues(
                    start = 16.dp, end = 16.dp,
                    top = padding.calculateTopPadding() + 8.dp,
                    bottom = padding.calculateBottomPadding() + 16.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(ListItemDefaults.SegmentedGap),
                content = content,
            )
        }
    }

    private fun LazyListScope.choices(list: List<Choice>, selected: String, onSelect: (String) -> Unit) {
        itemsIndexed(list) { index, choice ->
            val isSelected = choice.id == selected
            SegmentedListItem(
                selected = isSelected,
                onClick = { onSelect(choice.id) },
                shapes = ListItemDefaults.segmentedShapes(index, list.size),
                enabled = choice.enabled,
                leadingContent = { IconBadge(choice.icon, isSelected) },
                trailingContent = { RadioButton(selected = isSelected, onClick = null, enabled = choice.enabled) },
                supportingContent = if (choice.summary.isNotEmpty()) {
                    { Text(choice.summary) }
                } else {
                    null
                },
            ) { Text(choice.title) }
        }
    }

    @Composable
    private fun Log(state: androidx.compose.foundation.lazy.LazyListState) {
        SelectionContainer {
            LazyColumn(state = state, contentPadding = PaddingValues(12.dp)) {
                items(log.size) { i ->
                    Text(log[i], style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace))
                }
            }
        }
    }

    @Composable
    private fun IconBadge(icon: ImageVector, selected: Boolean) {
        val colors = MaterialTheme.colorScheme
        Box(
            Modifier.size(40.dp)
                .clip(if (selected) MaterialShapes.Cookie9Sided.toShape() else CircleShape)
                .background(if (selected) colors.primary else colors.secondaryContainer),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                icon, contentDescription = null, modifier = Modifier.size(24.dp),
                tint = if (selected) colors.onPrimary else colors.onSecondaryContainer,
            )
        }
    }

    @Composable
    private fun SectionTitle(text: String) {
        Text(
            text,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 4.dp, top = 8.dp, bottom = 4.dp),
        )
    }

    @Composable
    private fun Notice(text: String) {
        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.errorContainer,
                contentColor = MaterialTheme.colorScheme.onErrorContainer,
            ),
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
        ) {
            Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Icon(Icons.Outlined.Warning, contentDescription = null)
                Text(text, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }

    @Composable
    private fun Summary(text: String) {
        Card(
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Icon(Icons.Outlined.InstallDesktop, contentDescription = null)
                Text(text, style = MaterialTheme.typography.bodyLarge)
            }
        }
    }

    @Composable
    private fun Centered(content: @Composable () -> Unit) {
        Column(
            Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) { content() }
    }

    private fun date(utc: Long) =
        if (utc > 0) DateFormat.getDateTimeInstance().format(Date(utc * 1000)) else "?"
}

@Composable
private fun InstallerTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    MaterialExpressiveTheme(
        colorScheme = if (isSystemInDarkTheme()) dynamicDarkColorScheme(context)
                      else dynamicLightColorScheme(context),
        motionScheme = MotionScheme.expressive(),
        content = content,
    )
}
