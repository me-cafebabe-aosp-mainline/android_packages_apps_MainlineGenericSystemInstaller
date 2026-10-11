/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package device.mainline.generic.installer

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Like the scripts: room for user data, the partition table and the BIOS boot partition */
const val USERDATA_MIN_MIB = 4096L
const val OVERHEAD_MIB = 4L
const val METADATA_IMG_MIB = 64L

/** The system partitions in the layout of a whole disk installation */
private val SYSTEM_PARTITIONS = setOf("system", "system_dlkm", "vendor", "vendor_dlkm")

/** Where a part goes, an androidboot.mount_* value */
enum class Mount(val label: Int) {
    NONE(R.string.mount_none),
    PARTITIONS(R.string.mount_partitions),
    IMAGES(R.string.mount_images),
    IMAGES_RAM(R.string.mount_images_ram),
    DIRECTORIES(R.string.mount_dirs);

    /** The parameter value: directories are bind_mount_dir for user data, dirs for overlays */
    fun value(directories: String = "dirs") = when (this) {
        NONE -> ""
        PARTITIONS -> "std_parts"
        IMAGES -> "imgs"
        IMAGES_RAM -> "imgs_ram"
        DIRECTORIES -> directories
    }
}

val SYSTEM_MOUNTS = listOf(Mount.PARTITIONS, Mount.IMAGES, Mount.IMAGES_RAM)
val DISK_USERDATA_MOUNTS = listOf(Mount.PARTITIONS, Mount.IMAGES, Mount.DIRECTORIES)
val BESIDE_USERDATA_MOUNTS = listOf(Mount.DIRECTORIES, Mount.IMAGES)

enum class Fs(val value: String) {
    EXT4("ext4"),
    F2FS("f2fs");

    val label get() = value.uppercase()
}

/** A partition of the chosen layout: the name for the installer, its LAYOUT record */
data class LayoutRow(val name: String, val layout: PartitionLayout) {
    /** Overlay partitions: only created with a size */
    val optional get() = layout.defaultMiB == 0
}

/** What the user chose, and the rules between the choices */
class Wizard(val probe: ProbeResult) {
    var mode by mutableIntStateOf(InstallRequest.MODE_DISK)
    var target by mutableStateOf("")
    var cmdline by mutableStateOf(probe.system.defaultCmdline)

    // Whole disk
    var systemMount by mutableStateOf(Mount.PARTITIONS)
    var diskUserdataMount by mutableStateOf(Mount.PARTITIONS)
    var overlayMount by mutableStateOf(Mount.NONE)
    var androidFs by mutableStateOf(Fs.EXT4)
    /** Partition sizes in MiB as typed, by LAYOUT name, for the disk in sizesTarget */
    val sizes = mutableStateMapOf<String, String>()
    private var sizesTarget = ""

    // Beside another operating system
    var besideUserdataMount by mutableStateOf(Mount.DIRECTORIES)
    var linuxFirmware by mutableStateOf(false)

    var userdataFs by mutableStateOf(Fs.EXT4)
    var userdataGiB by mutableStateOf("16")
    var bootEntries by mutableStateOf(true)
    var allowDowngrade by mutableStateOf(false)

    val isDisk get() = mode == InstallRequest.MODE_DISK

    /** Sizes typed for another disk do not apply */
    fun keepSizesFor(disk: String) {
        if (sizesTarget != disk) {
            sizes.clear()
            sizesTarget = disk
        }
    }

    val isNtfsTarget get() =
        mode == InstallRequest.MODE_BESIDE && probe.partitions.any { it.name == target && it.fsType == "ntfs" }

    /** The partition has a Linux system whose firmware directory can be used */
    val hasLinuxFirmware get() =
        mode == InstallRequest.MODE_BESIDE && probe.partitions.any { it.name == target && it.linuxFirmware }

    /** Where the user data of a new installation goes; null for an upgrade */
    val userdataMount: Mount? get() = when (mode) {
        InstallRequest.MODE_DISK -> diskUserdataMount
        // Directories need a filesystem with Linux permissions
        InstallRequest.MODE_BESIDE -> if (isNtfsTarget) Mount.IMAGES else besideUserdataMount
        else -> null
    }

    /** Whole disk: images and directories go to an android partition, with the kernel */
    val hasAndroidPartition get() = systemMount != Mount.PARTITIONS || diskUserdataMount != Mount.PARTITIONS

    /** Directories only in the android partition: overlayfs refuses FAT32 */
    val overlayMounts get() = listOf(Mount.NONE, Mount.PARTITIONS, Mount.IMAGES, Mount.IMAGES_RAM) +
        listOfNotNull(Mount.DIRECTORIES.takeIf { hasAndroidPartition })

    val overlay get() = overlayMount.takeIf { it in overlayMounts } ?: Mount.NONE

    /** userdata gets a filesystem of its own: a partition or an image */
    val hasUserdataFs get() = userdataMount == Mount.PARTITIONS || userdataMount == Mount.IMAGES

    val userdataSizeMiB get() = (userdataGiB.toIntOrNull() ?: 16).coerceAtLeast(4) * 1024

    val hasBootEntries get() = when (mode) {
        InstallRequest.MODE_BESIDE -> true
        InstallRequest.MODE_UPGRADE ->
            probe.installations.any { it.id == target && it.kind == Installation.KIND_BESIDE }
        else -> false
    }

    /**
     * The partitions of the chosen layout but the last one (userdata or android), which takes
     * the rest. efi_android is efi with an android partition, which only holds GRUB.
     */
    fun layoutRows(): List<LayoutRow> = probe.layout.mapNotNull { l ->
        val shown = when (l.name) {
            "efi" -> !hasAndroidPartition
            "efi_android" -> hasAndroidPartition
            in SYSTEM_PARTITIONS -> systemMount == Mount.PARTITIONS
            "android" -> hasAndroidPartition && diskUserdataMount == Mount.PARTITIONS
            "metadata" -> diskUserdataMount == Mount.PARTITIONS
            else -> true
        }
        if (shown) LayoutRow(if (l.name == "efi_android") "efi" else l.name, l) else null
    }

    /** The size of a partition in MiB, 0 for overlay partitions not created */
    fun sizeMiB(row: LayoutRow): Long =
        if (row.optional && overlay != Mount.PARTITIONS) 0L
        else (sizes[row.layout.name] ?: "${row.layout.defaultMiB}").toLongOrNull() ?: 0L

    /** The partition that takes the rest of the disk */
    val restPartition get() = if (diskUserdataMount == Mount.PARTITIONS) "userdata" else "android"

    /** What the partition that takes the rest needs */
    val restNeedMiB: Long get() = if (diskUserdataMount == Mount.PARTITIONS) {
        USERDATA_MIN_MIB
    } else {
        (probe.layout.firstOrNull { it.name == "android" }?.minimumMiB?.toLong() ?: 0L) +
            if (diskUserdataMount == Mount.IMAGES) userdataSizeMiB + METADATA_IMG_MIB else USERDATA_MIN_MIB
    }

    fun request() = InstallRequest().also {
        it.mode = mode
        it.target = target
        // Strings must not be null: the daemon side is not nullable
        it.cmdline = cmdline.trim().takeIf { c -> c != probe.system.defaultCmdline }.orEmpty()
        it.bootEntries = bootEntries
        it.allowDowngrade = allowDowngrade
        it.mountSystem = if (isDisk) systemMount.value() else ""
        it.mountUserdata = userdataMount?.value("bind_mount_dir").orEmpty()
        it.mountOverlay = if (isDisk) overlay.value() else ""
        it.firmware = if (hasLinuxFirmware && linuxFirmware) "linux" else ""
        it.userdataFs = userdataFs.value
        it.userdataSizeMiB = userdataSizeMiB
        it.androidFs = androidFs.value
        it.sizes = if (isDisk) {
            layoutRows().filter { r -> !r.optional || overlay == Mount.PARTITIONS }.mapNotNull { r ->
                sizes[r.layout.name]?.toIntOrNull()?.takeIf { v -> v != r.layout.defaultMiB }?.let { v ->
                    PartitionSize().apply {
                        name = r.name
                        sizeMiB = v
                    }
                }
            }.toTypedArray()
        } else {
            emptyArray()
        }
    }
}
