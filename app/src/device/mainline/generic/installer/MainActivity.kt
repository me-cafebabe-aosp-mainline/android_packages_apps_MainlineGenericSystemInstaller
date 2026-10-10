/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer

import android.app.Activity
import android.os.Bundle
import android.os.PowerManager
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.text.format.Formatter
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.Executors

/** Choose what to do, where, with which options, confirm, install. */
class MainActivity : Activity() {
    private val executor = Executors.newSingleThreadExecutor()

    private lateinit var title: TextView
    private lateinit var content: FrameLayout
    private lateinit var primary: Button
    private lateinit var secondary: Button

    private var installer: ISystemInstaller? = null
    private lateinit var probe: ProbeResult
    private var mode = InstallRequest.MODE_DISK
    private var target = ""
    private var cmdline = ""
    private var userdataGiB = 16
    private var bootEntries = true
    private var allowDowngrade = false
    private var running = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        title = findViewById(R.id.title)
        content = findViewById(R.id.content)
        primary = findViewById(R.id.primary)
        secondary = findViewById(R.id.secondary)

        showMessage(getString(R.string.app_name), getString(R.string.loading), closeOnly = true)
        executor.execute { load() }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (!running) super.onBackPressed()
    }

    private fun load() {
        val service = Installer.get()
        val result = try {
            when {
                service == null -> Result.failure(Exception("systeminstallerd"))
                service.isRunning -> Result.failure(Exception(getString(R.string.running)))
                else -> Result.success(service.probe())
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
        runOnUiThread {
            result.onSuccess {
                installer = service
                probe = it
                cmdline = it.system.defaultCmdline
                showModes()
            }.onFailure {
                showMessage(
                    getString(R.string.app_name),
                    getString(R.string.unavailable, it.message), closeOnly = true,
                )
            }
        }
    }

    //
    // Steps
    //

    private fun showModes() {
        val s = probe.system
        val info = StringBuilder(
            getString(
                R.string.system_info, s.title, s.device,
                if (s.uefi) getString(R.string.firmware_uefi, s.efiBits)
                else getString(R.string.firmware_bios),
            )
        )
        if (s.secureBoot == 1) info.append("\n\n").append(getString(R.string.secure_boot_on))
        if (!s.sourceFound) info.append("\n\n").append(getString(R.string.no_source, s.sourceMessage))

        val group = RadioGroup(this)
        for ((m, text, summary) in listOf(
            Triple(InstallRequest.MODE_DISK, R.string.mode_disk, R.string.mode_disk_summary),
            Triple(InstallRequest.MODE_BESIDE, R.string.mode_beside, R.string.mode_beside_summary),
            Triple(InstallRequest.MODE_UPGRADE, R.string.mode_upgrade, R.string.mode_upgrade_summary),
        )) {
            group.addView(RadioButton(this).apply {
                id = View.generateViewId()
                this.text = "${getString(text)}\n${getString(summary)}"
                isChecked = m == mode
                isEnabled = s.sourceFound
                setOnClickListener { mode = m }
            })
        }

        setStep(R.string.mode_title, column(text(info.toString()), group))
        setButtons(R.string.next, s.sourceFound, { showTargets() }, R.string.close) { finish() }
    }

    private data class Choice(val id: String, val label: String, val enabled: Boolean)

    private fun choices(): List<Choice> = when (mode) {
        InstallRequest.MODE_DISK -> probe.disks.map {
            val label = getString(
                R.string.disk_label, it.name, size(it.sizeBytes), it.model,
            ) + if (it.removable) " " + getString(R.string.removable) else ""
            Choice(it.name, withReason(label, it.usable, it.reason), it.usable)
        }
        InstallRequest.MODE_BESIDE -> probe.partitions.map {
            val label = getString(
                R.string.partition_label, it.name, it.fsType, it.os.ifEmpty { it.label },
                if (it.freeMiB < 0) "?" else size(it.freeMiB * 1048576),
            )
            Choice(it.name, withReason(label, it.usable, it.reason), it.usable)
        }
        else -> probe.installations.map {
            val kind = when (it.kind) {
                Installation.KIND_DISK -> R.string.kind_disk
                Installation.KIND_BESIDE -> R.string.kind_beside
                else -> R.string.kind_package
            }
            val label = getString(R.string.installation_label, it.id, getString(kind), date(it.buildDateUtc))
            Choice(it.id, withReason(label, it.upgradable, it.reason), it.upgradable)
        }
    }

    private fun showTargets() {
        val list = choices()
        if (list.none { it.id == target && it.enabled }) target = ""
        val group = RadioGroup(this)
        for (c in list) {
            group.addView(RadioButton(this).apply {
                id = View.generateViewId()
                text = c.label
                isEnabled = c.enabled
                isChecked = c.id == target
                setOnClickListener {
                    target = c.id
                    primary.isEnabled = true
                }
            })
        }
        val title = when (mode) {
            InstallRequest.MODE_DISK -> R.string.target_disk
            InstallRequest.MODE_BESIDE -> R.string.target_beside
            else -> R.string.target_upgrade
        }
        setStep(title, if (list.isEmpty()) text(getString(R.string.target_none)) else column(group))
        setButtons(R.string.next, target.isNotEmpty(), { showOptions() }, R.string.back) { showModes() }
    }

    private fun isNtfsTarget() =
        mode == InstallRequest.MODE_BESIDE && probe.partitions.any { it.name == target && it.fsType == "ntfs" }

    private fun hasBootEntries() = when (mode) {
        InstallRequest.MODE_BESIDE -> true
        InstallRequest.MODE_UPGRADE ->
            probe.installations.any { it.id == target && it.kind == Installation.KIND_BESIDE }
        else -> false
    }

    private fun showOptions() {
        val views = mutableListOf<View>(text(getString(R.string.cmdline)))
        val cmdlineEdit = EditText(this).apply {
            setText(cmdline)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        }
        views += cmdlineEdit

        val sizeEdit = EditText(this).apply {
            setText(userdataGiB.toString())
            inputType = InputType.TYPE_CLASS_NUMBER
        }
        if (isNtfsTarget()) views += listOf(text(getString(R.string.userdata_size)), sizeEdit)

        val bootCheck = CheckBox(this).apply {
            text = "${getString(R.string.boot_entries)}\n${getString(R.string.boot_entries_summary)}"
            isChecked = bootEntries
        }
        if (hasBootEntries()) views += bootCheck

        val downgradeCheck = CheckBox(this).apply {
            text = "${getString(R.string.allow_downgrade)}\n${getString(R.string.allow_downgrade_summary)}"
            isChecked = allowDowngrade
        }
        if (mode == InstallRequest.MODE_UPGRADE) views += downgradeCheck

        fun save() {
            cmdline = cmdlineEdit.text.toString().trim()
            userdataGiB = sizeEdit.text.toString().toIntOrNull()?.coerceAtLeast(4) ?: userdataGiB
            bootEntries = bootCheck.isChecked
            allowDowngrade = downgradeCheck.isChecked
        }
        setStep(R.string.options_title, column(*views.toTypedArray()))
        setButtons(R.string.next, true, { save(); showConfirm() }, R.string.back) { save(); showTargets() }
    }

    private fun showConfirm() {
        val title = probe.system.title
        when (mode) {
            InstallRequest.MODE_DISK -> {
                val disk = probe.disks.first { it.name == target }
                val confirm = EditText(this).apply { hint = target }
                setStep(
                    R.string.confirm_title,
                    column(text(getString(R.string.confirm_disk, target, size(disk.sizeBytes))), confirm),
                )
                setButtons(R.string.install, false, { start() }, R.string.back) { showOptions() }
                confirm.addTextChangedListener(object : TextWatcher {
                    override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                    override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                    override fun afterTextChanged(s: Editable?) {
                        primary.isEnabled = s.toString() == target
                    }
                })
            }
            InstallRequest.MODE_BESIDE -> {
                setStep(R.string.confirm_title, text(getString(R.string.confirm_beside, title, target)))
                setButtons(R.string.install, true, { start() }, R.string.back) { showOptions() }
            }
            else -> {
                setStep(R.string.confirm_title, text(getString(R.string.confirm_upgrade, target, title)))
                setButtons(R.string.install, true, { start() }, R.string.back) { showOptions() }
            }
        }
    }

    private fun start() {
        val request = InstallRequest().apply {
            mode = this@MainActivity.mode
            target = this@MainActivity.target
            userdataSizeMiB = userdataGiB * 1024
            cmdline = if (this@MainActivity.cmdline == probe.system.defaultCmdline) ""
                      else this@MainActivity.cmdline
            bootEntries = this@MainActivity.bootEntries
            allowDowngrade = this@MainActivity.allowDowngrade
        }

        val step = text("")
        val bar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply { max = 100 }
        val log = TextView(this).apply { setTextIsSelectable(true) }
        val logScroll = ScrollView(this).apply { addView(log) }
        setStep(R.string.progress_title, LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(step)
            addView(bar)
            addView(logScroll, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        }, scroll = false)
        primary.visibility = View.GONE
        secondary.setText(R.string.cancel)
        secondary.isEnabled = true
        secondary.setOnClickListener {
            secondary.isEnabled = false
            executor.execute { runCatching { installer?.cancel() } }
        }
        running = true

        val callback = object : IProgressCallback.Stub() {
            override fun onProgress(percent: Int, text: String) = runOnUiThread {
                bar.progress = percent
                step.text = text
            }

            override fun onLog(line: String) = runOnUiThread {
                log.append(line + "\n")
                logScroll.post { logScroll.fullScroll(View.FOCUS_DOWN) }
            }

            override fun onDestructive() = runOnUiThread { secondary.isEnabled = false }

            override fun onFinished(success: Boolean, error: String) = runOnUiThread {
                running = false
                showDone(success, error, log.text.toString())
            }
        }
        executor.execute {
            try {
                installer!!.start(request, callback)
            } catch (e: Exception) {
                runOnUiThread {
                    running = false
                    showDone(false, e.message ?: e.toString(), "")
                }
            }
        }
    }

    private fun showDone(success: Boolean, error: String, log: String) {
        if (success) {
            showMessage(getString(R.string.done_title), getString(R.string.done_message), closeOnly = false)
            setButtons(R.string.restart, true, {
                getSystemService(PowerManager::class.java).reboot(null)
            }, R.string.close) { finish() }
        } else {
            val message = if (log.isEmpty()) error else "$error\n\n$log"
            showMessage(getString(R.string.failed_title), message, closeOnly = true)
        }
    }

    //
    // Helpers
    //

    private fun showMessage(titleText: String, message: String, closeOnly: Boolean) {
        title.text = titleText
        content.removeAllViews()
        content.addView(ScrollView(this).apply { addView(text(message).apply { setTextIsSelectable(true) }) })
        if (closeOnly) {
            primary.visibility = View.GONE
            secondary.visibility = View.VISIBLE
            secondary.isEnabled = true
            secondary.setText(R.string.close)
            secondary.setOnClickListener { finish() }
        }
    }

    private fun setStep(titleRes: Int, view: View, scroll: Boolean = true) {
        title.setText(titleRes)
        content.removeAllViews()
        content.addView(if (scroll) ScrollView(this).apply { addView(view) } else view)
    }

    private fun setButtons(
        primaryText: Int, primaryEnabled: Boolean, onPrimary: () -> Unit,
        secondaryText: Int, onSecondary: () -> Unit,
    ) {
        primary.visibility = View.VISIBLE
        primary.setText(primaryText)
        primary.isEnabled = primaryEnabled
        primary.setOnClickListener { onPrimary() }
        secondary.visibility = View.VISIBLE
        secondary.isEnabled = true
        secondary.setText(secondaryText)
        secondary.setOnClickListener { onSecondary() }
    }

    private fun text(s: String) = TextView(this).apply {
        text = s
        setPadding(0, 0, 0, 24)
    }

    private fun column(vararg views: View) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        views.forEach { addView(it) }
    }

    private fun withReason(label: String, usable: Boolean, reason: String) =
        if (usable || reason.isEmpty()) label else "$label\n$reason"

    private fun size(bytes: Long) = Formatter.formatFileSize(this, bytes)

    private fun date(utc: Long) =
        if (utc > 0) DateFormat.getDateTimeInstance().format(Date(utc * 1000)) else "?"
}
