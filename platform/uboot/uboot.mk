#
# Copyright (C) 2011 The Android Open-Source Project
# Copyright (C) 2018 GlobalLogic
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#-------------------------------------------------------------------------------
BSP_UBOOT_PATH := $(call my-dir)

UBOOT_SRC := external/u-boot
UBOOT_OUT := $(PRODUCT_OUT)/obj/UBOOT_OBJ

SYSFS_MMC0_PATH ?= soc/1c0f000.mmc
SYSFS_MMC1_PATH ?= soc/1c11000.mmc
RKTRUST_INI := RK3399TRUST.ini
UBOOT_EMMC_DEV_INDEX := 1
UBOOT_SD_DEV_INDEX := 0

UBOOT_KCFLAGS = \
    -fgnu89-inline \
    $(TARGET_BOOTLOADER_CFLAGS)

ifeq ($(TARGET_ARCH),arm64)
BL31_SET := BL31=$$(readlink -f $(ATF_BINARY))
endif

UMAKE := \
    PATH=/usr/bin:/bin:$$PATH \
    ARCH=$(TARGET_ARCH) \
    CROSS_COMPILE=$$(readlink -f $(CROSS_COMPILE)) \
    $(BL31_SET) \
    $(MAKE) \
    -C $(UBOOT_SRC) \
    O=$$(readlink -f $(UBOOT_OUT))

UBOOT_FRAGMENTS	+= device/glodroid/platform/common/uboot.config
UBOOT_FRAGMENT_EMMC := $(UBOOT_OUT)/uboot-emmc.config
UBOOT_FRAGMENT_SD := $(UBOOT_OUT)/uboot-sd.config

#-------------------------------------------------------------------------------
ifeq ($(PRODUCT_BOARD_PLATFORM),sunxi)
UBOOT_FRAGMENTS	+= device/glodroid/platform/common/sunxi/uboot.config
UBOOT_BINARY := $(UBOOT_OUT)/u-boot-sunxi-with-spl.bin
endif

ifeq ($(PRODUCT_BOARD_PLATFORM),broadcom)
UBOOT_FRAGMENTS	+= device/glodroid/platform/common/broadcom/uboot.config
UBOOT_BINARY := $(UBOOT_OUT)/u-boot.bin
RPI_FIRMWARE_DIR := vendor/raspberry/firmware
endif

ifeq ($(PRODUCT_BOARD_PLATFORM),rockchip)
UBOOT_FRAGMENTS	+= device/glodroid/platform/common/rockchip/uboot.config
UBOOT_BINARY := $(UBOOT_OUT)/idbloader.img
ROCKCHIP_FIRMWARE_DIR := vendor/rockchip/rkbin
UBOOT_EMMC_DEV_INDEX := 0
UBOOT_SD_DEV_INDEX := 1
SYSFS_MMC0_PATH := fe330000.sdhci
SYSFS_MMC1_PATH := fe320000.mmc
endif

$(UBOOT_FRAGMENT_EMMC):
	echo "CONFIG_FASTBOOT_FLASH_MMC_DEV=$(UBOOT_EMMC_DEV_INDEX)" > $@

$(UBOOT_FRAGMENT_SD):
	echo "CONFIG_FASTBOOT_FLASH_MMC_DEV=$(UBOOT_SD_DEV_INDEX)" > $@


$(UBOOT_BINARY): $(UBOOT_FRAGMENTS) $(UBOOT_FRAGMENT_SD) $(UBOOT_FRAGMENT_EMMC) $(sort $(shell find -L $(UBOOT_SRC))) $(ATF_BINARY)
	@echo "Building U-Boot: "
	@echo "TARGET_PRODUCT = " $(TARGET_PRODUCT):
	mkdir -p $(UBOOT_OUT)
	$(UMAKE) $(UBOOT_DEFCONFIG)
	PATH=/usr/bin:/bin $(UBOOT_SRC)/scripts/kconfig/merge_config.sh -m -O $(UBOOT_OUT)/ $(UBOOT_OUT)/.config $(UBOOT_FRAGMENTS) $(UBOOT_FRAGMENT_SD)
	$(UMAKE) olddefconfig
	$(UMAKE) KCFLAGS="$(UBOOT_KCFLAGS)"
	cp $@ $@.sd
ifneq ($(PRODUCT_HAS_EMMC),)
	$(UMAKE) $(UBOOT_DEFCONFIG)
	PATH=/usr/bin:/bin $(UBOOT_SRC)/scripts/kconfig/merge_config.sh -m -O $(UBOOT_OUT)/ $(UBOOT_OUT)/.config $(UBOOT_FRAGMENTS) $(UBOOT_FRAGMENT_EMMC)
	$(UMAKE) olddefconfig
	$(UMAKE) KCFLAGS="$(UBOOT_KCFLAGS)"
	cp $@ $@.emmc
endif

BOOTSCRIPT_GEN := $(PRODUCT_OUT)/gen/BOOTSCRIPT/boot.txt

$(BOOTSCRIPT_GEN): $(BSP_UBOOT_PATH)/bootscript.cpp $(BSP_UBOOT_PATH)/bootscript.h
	mkdir -p $(dir $@)
	$(CLANG) -E -P -Wno-invalid-pp-token $< -o $@ \
	    -Dplatform_$(PRODUCT_BOARD_PLATFORM) \
	    -Ddevice_$(PRODUCT_DEVICE) \
	    -D__SYSFS_MMC0_PATH__=$(SYSFS_MMC0_PATH) \
	    -D__SYSFS_MMC1_PATH__=$(SYSFS_MMC1_PATH) \

$(UBOOT_OUT)/boot.scr: $(BOOTSCRIPT_GEN) $(UBOOT_BINARY)
	$(UBOOT_OUT)/tools/mkimage -A arm -O linux -T script -C none -a 0 -e 0 -d $< $@

$(PRODUCT_OUT)/env.img: $(UBOOT_OUT)/boot.scr
	rm -f $@
	/sbin/mkfs.vfat -n "uboot-scr" -S 512 -C $@ 256
	/usr/bin/mcopy -i $@ -s $< ::$(notdir $<)

$(UBOOT_OUT)/bootloader.img: $(UBOOT_BINARY)
	cp -f $< $@
	dd if=/dev/null of=$@ bs=1 count=1 seek=$$(( 2048 * 1024 - 256 * 512 ))


ifeq ($(PRODUCT_BOARD_PLATFORM),sunxi)
$(PRODUCT_OUT)/bootloader-sd.img: $(UBOOT_BINARY)
	cp -f $<.sd $@
	dd if=/dev/null of=$@ bs=1 count=1 seek=$$(( 2048 * 1024 - 256 * 512 ))
endif

ifeq ($(PRODUCT_BOARD_PLATFORM),rockchip)
$(PRODUCT_OUT)/bootloader-sd.img: $(UBOOT_BINARY)
	#Script for build uboot: https://github.com/armbian/build/blob/master/config/sources/families/include/rockchip64_common.inc
	$(ROCKCHIP_FIRMWARE_DIR)/tools/mkimage -n rk3399 -T rksd -d $(ROCKCHIP_FIRMWARE_DIR)/bin/rk33/rk3399_ddr_933MHz_v1.24.bin $(UBOOT_OUT)/idbloader_externel.img
	cat $(ROCKCHIP_FIRMWARE_DIR)/bin/rk33/rk3399_miniloader_v1.26.bin >> $(UBOOT_OUT)/idbloader_externel.img
	$(ROCKCHIP_FIRMWARE_DIR)/tools/loaderimage --pack --uboot $(UBOOT_OUT)/u-boot-dtb.bin $(UBOOT_OUT)/uboot.img 0x200000
	- mkdir $(UBOOT_OUT)/bin
	(cp -r $(ROCKCHIP_FIRMWARE_DIR)/bin/rk33 $(UBOOT_OUT)/bin && cp $(ROCKCHIP_FIRMWARE_DIR)/RKTRUST/$(RKTRUST_INI) $(UBOOT_OUT) && cp $(ROCKCHIP_FIRMWARE_DIR)/tools/trust_merger $(UBOOT_OUT)/tools/trust_merger && cd $(UBOOT_OUT) && ./tools/trust_merger $(RKTRUST_INI))
	dd if=$(UBOOT_OUT)/idbloader_externel.img of=$@ seek=0
	dd if=$(UBOOT_OUT)/uboot.img of=$@ seek=$$(( 16384 - 64 ))
	dd if=$(UBOOT_OUT)/trust.img of=$@ seek=$$(( 24576 - 64 ))
	dd if=/dev/null of=$@ bs=1 count=1 seek=$$(( 16384 * 1024 - 64 * 512 ))
endif


ifeq ($(PRODUCT_BOARD_PLATFORM),broadcom)
BOOT_FILES := \
    $(RPI_FIRMWARE_DIR)/boot/bootcode.bin \
    $(RPI_FIRMWARE_DIR)/boot/start.elf \
    $(RPI_FIRMWARE_DIR)/boot/start4.elf \
    $(RPI_FIRMWARE_DIR)/boot/fixup.dat \
    $(RPI_FIRMWARE_DIR)/boot/fixup4.dat \
    $(RPI_FIRMWARE_DIR)/boot/bcm2710-rpi-3-b.dtb \
    $(RPI_FIRMWARE_DIR)/boot/bcm2710-rpi-3-b-plus.dtb \
    $(PRODUCT_OUT)/obj/KERNEL_OBJ/arch/$(TARGET_ARCH)/boot/dts/$(KERNEL_DTB_FILE) \

OVERLAY_FILES := $(sort $(shell find -L $(RPI_FIRMWARE_DIR)/boot/overlays))

$(PRODUCT_OUT)/bootloader-sd.img: $(UBOOT_BINARY) $(BOOT_FILES) $(OVERLAY_FILES) $(ATF_BINARY) $(RPI_CONFIG) $(KERNEL_BINARY)
	dd if=/dev/null of=$@ bs=1 count=1 seek=$$(( 128 * 1024 * 1024 - 256 * 512 ))
	/sbin/mkfs.vfat -F 32 -n boot $@
	/usr/bin/mcopy -i $@ $(UBOOT_BINARY) ::$(notdir $(UBOOT_BINARY))
	/usr/bin/mcopy -i $@ $(ATF_BINARY) ::$(notdir $(ATF_BINARY))
	/usr/bin/mcopy -i $@ $(RPI_CONFIG) ::$(notdir $(RPI_CONFIG))
	/usr/bin/mcopy -i $@ $(BOOT_FILES) ::
	/usr/bin/mmd -i $@ ::overlays
	/usr/bin/mcopy -i $@ $(OVERLAY_FILES) ::overlays/
endif

ifneq ($(PRODUCT_HAS_EMMC),)
ifeq ($(PRODUCT_BOARD_PLATFORM),sunxi)
$(PRODUCT_OUT)/bootloader-emmc.img: $(UBOOT_BINARY)
	cp -f $<.emmc $@
	dd if=/dev/null of=$@ bs=1 count=1 seek=$$(( 2048 * 1024 - 256 * 512 ))
endif
endif
