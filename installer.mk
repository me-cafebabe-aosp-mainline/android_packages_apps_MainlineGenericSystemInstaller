#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Inherited by device/mainline/generic/device.mk.
#

PRODUCT_PACKAGES += \
    SystemInstaller \
    systeminstaller \
    systeminstallerd

# A board variable: product makefiles are read first, and the BoardConfig
# files of the device trees append to it.
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += packages/apps/MainlineGenericSystemInstaller/sepolicy
