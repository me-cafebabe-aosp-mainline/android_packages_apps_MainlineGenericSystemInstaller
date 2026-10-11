/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)

package device.mainline.generic.installer

import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.InstallDesktop
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeFlexibleTopAppBar
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.SegmentedListItem
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.ToggleButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.toShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import java.text.DateFormat
import java.util.Date
import java.util.Locale

//
// Formatting
//

/** Binary units only, like the partition sizes: MiB below 1 GiB, GiB above */
fun formatMiB(mib: Long): String = when {
    mib < 1024 -> "$mib MiB"
    mib % 1024 == 0L -> "${mib / 1024} GiB"
    else -> String.format(Locale.getDefault(), "%.1f GiB", mib / 1024.0)
}

fun formatBytes(bytes: Long) = formatMiB(bytes / 1048576)

fun formatDate(utc: Long): String =
    if (utc > 0) DateFormat.getDateTimeInstance().format(Date(utc * 1000)) else "?"

//
// Pages
//

data class Action(val label: String, val enabled: Boolean = true, val onClick: () -> Unit)

@Composable
fun InstallerTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    MaterialExpressiveTheme(
        colorScheme = if (isSystemInDarkTheme()) dynamicDarkColorScheme(context)
                      else dynamicLightColorScheme(context),
        motionScheme = MotionScheme.expressive(),
        content = content,
    )
}

/** A step: a large app bar, the content, Back/Next style buttons at the bottom */
@Composable
fun Page(
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
                subtitle = subtitle?.let { { Text(it, maxLines = 2) } },
                scrollBehavior = scrollBehavior,
            )
        },
        bottomBar = {
            // Opaque: the list scrolls below it
            Surface(color = MaterialTheme.colorScheme.background) {
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
            }
        },
        content = content,
    )
}

@Composable
fun ListPage(
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

@Composable
fun Centered(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) { content() }
}

//
// Choices
//

/** One of the things to choose from on a page */
data class Choice(
    val id: String,
    val icon: ImageVector,
    val title: String,
    val summary: String,
    val enabled: Boolean,
)

fun LazyListScope.choices(list: List<Choice>, selected: String, onSelect: (String) -> Unit) {
    itemsIndexed(list) { index, choice ->
        val isSelected = choice.id == selected
        SegmentedListItem(
            selected = isSelected,
            onClick = { onSelect(choice.id) },
            shapes = ListItemDefaults.segmentedShapes(index, list.size),
            enabled = choice.enabled,
            leadingContent = { IconBadge(choice.icon, isSelected) },
            trailingContent = { RadioButton(selected = isSelected, onClick = null, enabled = choice.enabled) },
            supportingContent = choice.summary.takeIf { it.isNotEmpty() }?.let { { Text(it) } },
        ) { Text(choice.title) }
    }
}

/** An on/off option */
data class SwitchItem(val title: String, val summary: String, val checked: Boolean, val onChange: (Boolean) -> Unit)

fun LazyListScope.switches(list: List<SwitchItem>) {
    itemsIndexed(list) { index, item ->
        SegmentedListItem(
            onClick = { item.onChange(!item.checked) },
            shapes = ListItemDefaults.segmentedShapes(index, list.size),
            supportingContent = { Text(item.summary) },
            trailingContent = { Switch(checked = item.checked, onCheckedChange = null) },
        ) { Text(item.title) }
    }
}

/** A few choices side by side, connected buttons */
@Composable
fun <T> ToggleRow(choices: List<T>, selected: T, label: @Composable (T) -> String, onSelect: (T) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween)) {
        choices.forEachIndexed { i, choice ->
            ToggleButton(
                checked = choice == selected,
                onCheckedChange = { onSelect(choice) },
                shapes = when (i) {
                    0 -> ButtonGroupDefaults.connectedLeadingButtonShapes()
                    choices.lastIndex -> ButtonGroupDefaults.connectedTrailingButtonShapes()
                    else -> ButtonGroupDefaults.connectedMiddleButtonShapes()
                },
                modifier = Modifier.weight(1f),
            ) { Text(label(choice), maxLines = 1) }
        }
    }
}

/** More choices, or choices with longer labels: a scrollable row of chips */
@Composable
fun <T> ChipChoice(choices: List<T>, selected: T, label: @Composable (T) -> String, onSelect: (T) -> Unit) {
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(choices.size) { i ->
            val choice = choices[i]
            FilterChip(
                selected = choice == selected,
                onClick = { onSelect(choice) },
                label = { Text(label(choice)) },
            )
        }
    }
}

//
// Small pieces
//

@Composable
fun SectionTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 4.dp, top = 8.dp, bottom = 4.dp),
    )
}

/** Explains the choice above it */
@Composable
fun Hint(text: String, error: Boolean = false) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        color = if (error) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 4.dp),
    )
}

/** Something that goes wrong, or is lost */
@Composable
fun Notice(text: String) {
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

/** What is going to happen */
@Composable
fun Summary(text: String) {
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
fun IconBadge(icon: ImageVector, selected: Boolean) {
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
fun Dot(color: Color) {
    Box(Modifier.size(12.dp).clip(CircleShape).background(color))
}

/** How a disk is shared, each part at least a sliver */
@Composable
fun UsageBar(parts: List<Pair<Long, Color>>) {
    val total = parts.sumOf { maxOf(it.first, 0L) }.coerceAtLeast(1L)
    Row(
        Modifier.fillMaxWidth().height(32.dp).clip(RoundedCornerShape(16.dp)),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        parts.filter { it.first > 0 }.forEach { (mib, color) ->
            Box(Modifier.weight(maxOf(mib.toFloat() / total, 0.015f)).fillMaxHeight().background(color))
        }
    }
}

/** Lines of the installer's output, selectable */
@Composable
fun LogView(lines: List<String>, state: LazyListState) {
    SelectionContainer {
        LazyColumn(state = state, contentPadding = PaddingValues(12.dp)) {
            items(lines.size) { i ->
                Text(lines[i], style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace))
            }
        }
    }
}
