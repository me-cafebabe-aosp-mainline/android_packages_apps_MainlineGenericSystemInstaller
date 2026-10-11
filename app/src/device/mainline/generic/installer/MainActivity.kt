/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer

import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import java.util.concurrent.Executors

private enum class Screen { LOADING, MODES, TARGETS, PARTITIONS, OPTIONS, CONFIRM, PROGRESS, RESULT }

/**
 * The steps: what to do, where, partition sizes (whole disk), options, confirm, install. The
 * choices are in Wizard, the screens in *Screen(s).kt.
 */
class MainActivity : ComponentActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private var installer: ISystemInstaller? = null

    private var screen by mutableStateOf(Screen.LOADING)
    private var wizard by mutableStateOf<Wizard?>(null)
    private var run by mutableStateOf(InstallRun())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Installations take a while, and the screen is the only feedback
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
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
                wizard = Wizard(probe)
                screen = Screen.MODES
            }.onFailure {
                run = InstallRun().apply {
                    finished = false
                    error = getString(R.string.unavailable, it.message)
                }
                screen = Screen.RESULT
            }
        }
    }

    private fun start(w: Wizard) {
        val request = w.request()
        val r = InstallRun()
        run = r
        screen = Screen.PROGRESS
        val callback = object : IProgressCallback.Stub() {
            override fun onProgress(percent: Int, text: String) = runOnUiThread {
                r.progress = percent / 100f
                r.step = text
            }

            override fun onLog(line: String) = runOnUiThread { r.log += line }

            override fun onDestructive() = runOnUiThread { r.destructive = true }

            override fun onFinished(success: Boolean, error: String) = runOnUiThread {
                r.error = error
                r.finished = success
            }
        }
        executor.execute {
            runCatching { installer!!.start(request, callback) }.onFailure {
                runOnUiThread {
                    r.error = it.message ?: it.toString()
                    r.finished = false
                }
            }
        }
    }

    private fun cancel() {
        run.destructive = true
        executor.execute { runCatching { installer?.cancel() } }
    }

    private fun saveLog(uri: Uri) {
        val text = run.text()
        executor.execute { runCatching { contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray()) } } }
    }

    private fun back() {
        screen = when (screen) {
            Screen.TARGETS -> Screen.MODES
            Screen.PARTITIONS -> Screen.TARGETS
            Screen.OPTIONS -> if (wizard?.isDisk == true) Screen.PARTITIONS else Screen.TARGETS
            Screen.CONFIRM -> Screen.OPTIONS
            else -> {
                finish()
                screen
            }
        }
    }

    @Composable
    private fun App() {
        BackHandler(enabled = screen != Screen.PROGRESS) { back() }
        BackHandler(enabled = screen == Screen.PROGRESS) {}
        // The background and content color of every screen, also during transitions
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            AnimatedContent(targetState = screen, label = "screen") { s ->
                val w = wizard
                when {
                    s == Screen.LOADING -> LoadingScreen()
                    s == Screen.PROGRESS -> ProgressScreen(run, onNext = { screen = Screen.RESULT }, onCancel = ::cancel)
                    s == Screen.RESULT -> ResultScreen(
                        run,
                        onSaveLog = ::saveLog,
                        onRestart = { getSystemService(PowerManager::class.java).reboot(null) },
                        onClose = ::finish,
                    )
                    w == null -> LoadingScreen()
                    s == Screen.MODES -> ModesScreen(w, onNext = { screen = Screen.TARGETS }, onClose = ::finish)
                    s == Screen.TARGETS -> TargetsScreen(w, onBack = ::back, onNext = {
                        if (w.isDisk) {
                            w.keepSizesFor(w.target)
                            screen = Screen.PARTITIONS
                        } else {
                            screen = Screen.OPTIONS
                        }
                    })
                    s == Screen.PARTITIONS -> PartitionsScreen(w, onNext = { screen = Screen.OPTIONS }, onBack = ::back)
                    s == Screen.OPTIONS -> OptionsScreen(w, onNext = { screen = Screen.CONFIRM }, onBack = ::back)
                    else -> ConfirmScreen(w, onInstall = { start(w) }, onBack = ::back)
                }
            }
        }
    }
}
