# SPDX-License-Identifier: Apache-2.0
#
# Copyright (C) 2020 Daniil PEtrov (daniil.petrov@globallogic.com)

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, device/glodroid/opi4/device.mk)

PRODUCT_BOARD_PLATFORM := rockchip
PRODUCT_NAME := opi4
PRODUCT_DEVICE := opi4
PRODUCT_BRAND := OrangePI
PRODUCT_MODEL := opi4
PRODUCT_MANUFACTURER := xunlong

UBOOT_DEFCONFIG := orangepi-rk3399_defconfig
ATF_PLAT        := rk3399

KERNEL_DEFCONFIG := $(LOCAL_PATH)/rockchip_defconfig

KERNEL_DTB_FILE := rockchip/rk3399-orangepi.dtb
