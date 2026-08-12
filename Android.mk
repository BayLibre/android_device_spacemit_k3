LOCAL_PATH := $(call my-dir)

#
# Copy K3 (Pico-ITX) bootloader prebuilts and flash script to PRODUCT_OUT.
# Source: vendor/spacemit/k3/bootloader/ (populated from the K3 U-Boot build).
#
# K3 boots from SPI-NOR: BROM -> FSBL (SPL + AIHD header) -> OpenSBI -> U-Boot.
# Unlike the 2022.10 K1 tree, the K3 u-boot.itb is built by binman and already
# bundles the OpenSBI fw_dynamic firmware, U-Boot proper and the control FDT.
# The flash script still references a fw_dynamic.itb slot, so the raw fw_dynamic
# binary is staged under that name as a fallback (prefer .itb if one is built).
#
BL_PREBUILT := vendor/spacemit/k3/bootloader

# Every device/*/Android.mk is parsed for all products, and these rules write to
# the shared $(PRODUCT_OUT). Gate on TARGET_DEVICE so the K3 bootloader rules
# only fire for a K3 build; otherwise they collide with the K1 rules, which
# define the same $(PRODUCT_OUT)/u-boot.itb (and friends).
ifneq ($(filter k3%, $(TARGET_DEVICE)),)
ifneq ($(wildcard $(BL_PREBUILT)/u-boot-release.itb),)

SPACEMIT_K3_FLASH_FILES :=

# u-boot.itb (opensbi + u-boot + control FDT)
$(PRODUCT_OUT)/u-boot.itb: $(BL_PREBUILT)/u-boot-release.itb
	cp $< $@
SPACEMIT_K3_FLASH_FILES += $(PRODUCT_OUT)/u-boot.itb

# fw_dynamic.itb (prefer .itb, fallback to the raw fw_dynamic bin)
ifneq ($(wildcard $(BL_PREBUILT)/fw_dynamic.itb),)
$(PRODUCT_OUT)/fw_dynamic.itb: $(BL_PREBUILT)/fw_dynamic.itb
	cp $< $@
else
$(PRODUCT_OUT)/fw_dynamic.itb: $(BL_PREBUILT)/fw_dynamic-release.bin
	cp $< $@
endif
SPACEMIT_K3_FLASH_FILES += $(PRODUCT_OUT)/fw_dynamic.itb

# env.bin
$(PRODUCT_OUT)/env.bin: $(BL_PREBUILT)/env-release.bin
	cp $< $@
SPACEMIT_K3_FLASH_FILES += $(PRODUCT_OUT)/env.bin

# factory/FSBL.bin (SPL + BROM AIHD header + cert chain; fallback to raw SPL)
ifneq ($(wildcard $(BL_PREBUILT)/factory/FSBL.bin),)
$(PRODUCT_OUT)/factory/FSBL.bin: $(BL_PREBUILT)/factory/FSBL.bin
	mkdir -p $(dir $@)
	cp $< $@
else
$(PRODUCT_OUT)/factory/FSBL.bin: $(BL_PREBUILT)/u-boot-spl-release.bin
	mkdir -p $(dir $@)
	cp $< $@
endif
SPACEMIT_K3_FLASH_FILES += $(PRODUCT_OUT)/factory/FSBL.bin

# factory/bootinfo_spinor.bin (BROM header for SPI-NOR boot; K3 boots from NOR)
$(PRODUCT_OUT)/factory/bootinfo_spinor.bin: $(BL_PREBUILT)/factory/bootinfo_spinor.bin
	mkdir -p $(dir $@)
	cp $< $@
SPACEMIT_K3_FLASH_FILES += $(PRODUCT_OUT)/factory/bootinfo_spinor.bin

# factory/bootinfo_spinand.bin (optional, SPI-NAND boot media)
ifneq ($(wildcard $(BL_PREBUILT)/factory/bootinfo_spinand.bin),)
$(PRODUCT_OUT)/factory/bootinfo_spinand.bin: $(BL_PREBUILT)/factory/bootinfo_spinand.bin
	mkdir -p $(dir $@)
	cp $< $@
SPACEMIT_K3_FLASH_FILES += $(PRODUCT_OUT)/factory/bootinfo_spinand.bin
endif

# factory/bootinfo_block.bin (optional, eMMC/block boot media)
ifneq ($(wildcard $(BL_PREBUILT)/factory/bootinfo_block.bin),)
$(PRODUCT_OUT)/factory/bootinfo_block.bin: $(BL_PREBUILT)/factory/bootinfo_block.bin
	mkdir -p $(dir $@)
	cp $< $@
SPACEMIT_K3_FLASH_FILES += $(PRODUCT_OUT)/factory/bootinfo_block.bin
endif

# factory/ec.bin (optional, Pico-ITX CrosEC RW firmware for "oem ec:flash")
ifneq ($(wildcard $(BL_PREBUILT)/factory/ec.bin),)
$(PRODUCT_OUT)/factory/ec.bin: $(BL_PREBUILT)/factory/ec.bin
	mkdir -p $(dir $@)
	cp $< $@
SPACEMIT_K3_FLASH_FILES += $(PRODUCT_OUT)/factory/ec.bin
endif

# partition_nor.json: SPI-NOR (MTD) bootloader layout (board-specific, optional)
ifneq ($(wildcard $(BL_PREBUILT)/partition_nor.json),)
$(PRODUCT_OUT)/partition_nor.json: $(BL_PREBUILT)/partition_nor.json
	cp $< $@
SPACEMIT_K3_FLASH_FILES += $(PRODUCT_OUT)/partition_nor.json
endif

# partition_android.json: Android GPT layout (board-specific, optional)
ifneq ($(wildcard $(BL_PREBUILT)/partition_android.json),)
$(PRODUCT_OUT)/partition_android.json: $(BL_PREBUILT)/partition_android.json
	cp $< $@
SPACEMIT_K3_FLASH_FILES += $(PRODUCT_OUT)/partition_android.json
endif

# flash script
$(PRODUCT_OUT)/flash_pico_itx.sh: device/spacemit/k3/flash_pico_itx.sh
	cp $< $@
	chmod +x $@
SPACEMIT_K3_FLASH_FILES += $(PRODUCT_OUT)/flash_pico_itx.sh

droidcore: $(SPACEMIT_K3_FLASH_FILES)

endif # u-boot-release.itb exists
endif # TARGET_DEVICE is k3*
