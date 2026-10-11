/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

@file:OptIn(ExperimentalMaterial3ExpressiveApi::class)

package device.mainline.generic.installer

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Save
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Text
import androidx.compose.material3.toShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/** An installation as it runs, from the callbacks of the daemon */
class InstallRun {
    var progress by mutableFloatStateOf(0f)
    var step by mutableStateOf("")
    /** cancel() is refused from here on */
    var destructive by mutableStateOf(false)
    /** null while it runs. The progress page stays until Next. */
    var finished by mutableStateOf<Boolean?>(null)
    var error by mutableStateOf("")
    val log = mutableStateListOf<String>()

    /** What Save log writes: the error, then the output */
    fun text() = buildString {
        if (finished == false && error.isNotEmpty()) append(error).append("\n\n")
        log.forEach { append(it).append('\n') }
    }
}

@Composable
fun ProgressScreen(run: InstallRun, onNext: () -> Unit, onCancel: () -> Unit) {
    val animated by animateFloatAsState(
        run.progress, MaterialTheme.motionScheme.slowSpatialSpec<Float>(), label = "progress",
    )
    val logState = rememberLazyListState()
    LaunchedEffect(run.log.size) { if (run.log.isNotEmpty()) logState.animateScrollToItem(run.log.lastIndex) }
    Page(
        title = stringResource(R.string.progress_title),
        subtitle = when (run.finished) {
            true -> stringResource(R.string.progress_done)
            false -> stringResource(R.string.failed_title)
            null -> run.step.ifEmpty { null }
        },
        primary = Action(stringResource(R.string.next), run.finished != null, onNext),
        secondary = Action(stringResource(R.string.cancel), !run.destructive && run.finished == null, onCancel),
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            LinearWavyProgressIndicator(progress = { animated }, modifier = Modifier.fillMaxWidth())
            Text("${(run.progress * 100).toInt()} %", style = MaterialTheme.typography.labelLarge)
            OutlinedCard(Modifier.fillMaxWidth().weight(1f)) { LogView(run.log, logState) }
        }
    }
}

/** Installed or failed, with the log */
@Composable
fun ResultScreen(run: InstallRun, onSaveLog: (Uri) -> Unit, onRestart: () -> Unit, onClose: () -> Unit) {
    val success = run.finished == true
    val saveLog = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/plain")) { uri ->
        uri?.let(onSaveLog)
    }
    Page(
        title = "",
        primary = if (success) Action(stringResource(R.string.restart), onClick = onRestart) else null,
        secondary = Action(stringResource(R.string.close), onClick = onClose),
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            val colors = MaterialTheme.colorScheme
            Spacer(Modifier.height(16.dp))
            Box(
                Modifier.size(120.dp)
                    .clip(MaterialShapes.Cookie12Sided.toShape())
                    .background(if (success) colors.primaryContainer else colors.errorContainer),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (success) Icons.Outlined.CheckCircle else Icons.Outlined.ErrorOutline,
                    contentDescription = null,
                    modifier = Modifier.size(56.dp),
                    tint = if (success) colors.onPrimaryContainer else colors.onErrorContainer,
                )
            }
            Text(
                stringResource(if (success) R.string.done_title else R.string.failed_title),
                style = MaterialTheme.typography.headlineMedium,
                textAlign = TextAlign.Center,
            )
            SelectionContainer {
                Text(
                    if (success) stringResource(R.string.done_message) else run.error,
                    style = MaterialTheme.typography.bodyLarge,
                    textAlign = TextAlign.Center,
                )
            }
            if (run.log.isNotEmpty()) {
                FilledTonalButton(onClick = { saveLog.launch("installer.log") }, shapes = ButtonDefaults.shapes()) {
                    Icon(Icons.Outlined.Save, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.save_log))
                }
                if (!success) {
                    OutlinedCard(Modifier.fillMaxWidth().weight(1f)) { LogView(run.log, rememberLazyListState()) }
                }
            }
        }
    }
}
