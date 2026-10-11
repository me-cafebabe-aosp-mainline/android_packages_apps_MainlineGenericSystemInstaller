#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Build tasks, included by build/tasks of device/mainline/generic.
#

SYSTEMINSTALLER_PATH := packages/apps/MainlineGenericSystemInstaller

##### diskimage #####
# Flashable disk image: the layout of a whole disk installation.

MAINLINE_GENERIC_DISKIMAGE_USERDATA_SIZE ?= 4096
# ext4 or f2fs
MAINLINE_GENERIC_DISKIMAGE_USERDATA_FS ?= ext4

INSTALLED_DISKIMAGE_TARGET := $(PRODUCT_OUT)/$(BOOTMGR_ARTIFACT_FILENAME_PREFIX)-disk.img

DISKIMAGE_GRUB_DIR := $(TARGET_OUT_SYSTEM_EXT)/etc/systeminstaller/grub
ifeq ($(TARGET_ARCH),x86_64)
DISKIMAGE_GRUB_FILES := i386-efi.efi i386-pc-boot.img i386-pc-core.img unicode.pf2 x86_64-efi.efi
else ifeq ($(TARGET_ARCH),arm64)
DISKIMAGE_GRUB_FILES := arm64-efi.efi unicode.pf2
endif

DISKIMAGE_IMAGES := system system_dlkm vendor vendor_dlkm
DISKIMAGE_MTOOLS := prebuilts/bootmgr/tools/$(HOST_PREBUILT_TAG)/bin/mtools
DISKIMAGE_LOADER := prebuilts/bootmgr/lib64/ld-linux-x86-64.so.2

INSTALLED_DISKIMAGE_TARGET_DEPS := \
    $(addprefix $(DISKIMAGE_GRUB_DIR)/,$(DISKIMAGE_GRUB_FILES)) \
    $(addprefix $(PRODUCT_OUT)/,$(addsuffix .img,$(DISKIMAGE_IMAGES))) \
    $(PRODUCT_OUT)/kernel \
    $(INSTALLED_RAMDISK_ALL_COMBINED_TARGET) \
    $(HOST_OUT_EXECUTABLES)/mke2fs \
    $(if $(filter f2fs,$(MAINLINE_GENERIC_DISKIMAGE_USERDATA_FS)),$(HOST_OUT_EXECUTABLES)/make_f2fs) \
    $(HOST_OUT_EXECUTABLES)/sgdisk \
    $(wildcard $(SYSTEMINSTALLER_PATH)/scripts/make-diskimage.sh $(SYSTEMINSTALLER_PATH)/scripts/lib/*.sh) \
    $(TARGET_LINUX_FIRMWARE_IMAGE)

# $(1): output file
define make-diskimage-target
	sh $(SYSTEMINSTALLER_PATH)/scripts/make-diskimage.sh \
		--out $(1) \
		--sgdisk $(HOST_OUT_EXECUTABLES)/sgdisk \
		--mke2fs $(HOST_OUT_EXECUTABLES)/mke2fs \
		--mtools $(DISKIMAGE_MTOOLS) \
		--loader $(DISKIMAGE_LOADER) \
		--grub $(DISKIMAGE_GRUB_DIR) \
		--kernel $(PRODUCT_OUT)/kernel \
		--ramdisk $(INSTALLED_RAMDISK_ALL_COMBINED_TARGET) \
		$(if $(TARGET_LINUX_FIRMWARE_IMAGE),--firmware $(TARGET_LINUX_FIRMWARE_IMAGE)) \
		$(foreach i,$(DISKIMAGE_IMAGES),--image $(i)=$(PRODUCT_OUT)/$(i).img) \
		--title "$(BOOTMGR_ANDROID_DISTRIBUTION_NAME)" \
		--cmdline "$(strip $(BOARD_KERNEL_CMDLINE))" \
		--userdata-size $(MAINLINE_GENERIC_DISKIMAGE_USERDATA_SIZE) \
		--userdata-fs $(MAINLINE_GENERIC_DISKIMAGE_USERDATA_FS) \
		--make-f2fs $(HOST_OUT_EXECUTABLES)/make_f2fs
endef

$(INSTALLED_DISKIMAGE_TARGET): $(INSTALLED_DISKIMAGE_TARGET_DEPS)
	$(call pretty,"Target disk image: $@")
	$(call make-diskimage-target,$@)

.PHONY: diskimage
diskimage: $(INSTALLED_DISKIMAGE_TARGET)

.PHONY: diskimage-nodeps
diskimage-nodeps:
	@echo "make $(INSTALLED_DISKIMAGE_TARGET): ignoring dependencies"
	$(call make-diskimage-target,$(INSTALLED_DISKIMAGE_TARGET))
