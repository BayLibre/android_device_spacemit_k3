#
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Generate dtb.img from DTB files

ifneq ($(filter k3%, $(TARGET_DEVICE)),)

MKDTIMG := prebuilts/misc/linux-x86/libufdt/mkdtimg
DTBIMAGE := $(PRODUCT_OUT)/dtb.img

LOCAL_DTB := device/spacemit/kernel/$(TARGET_KERNEL_USE)

# Every K3 DTB the selected kernel ships, packed into dtb.img, which
# BOARD_INCLUDE_DTB_IN_BOOTIMG puts in vendor_boot. Discovered rather than
# listed so that switching TARGET_KERNEL_USE cannot ask for a board the
# selected kernel does not build.
DTB_FILES := $(wildcard $(LOCAL_DTB)/k3-*.dtb)

ifeq ($(DTB_FILES),)
$(error No K3 DTB in $(LOCAL_DTB) (TARGET_KERNEL_USE=$(TARGET_KERNEL_USE)))
endif

$(DTBIMAGE): $(DTB_FILES) $(MKDTIMG)
	$(MKDTIMG) create $@ --page_size=4096 $(DTB_FILES)

include $(CLEAR_VARS)
LOCAL_MODULE := dtbimage
LOCAL_LICENSE_KINDS := legacy_notice
LOCAL_LICENSE_CONDITIONS := notice
LOCAL_ADDITIONAL_DEPENDENCIES := $(DTBIMAGE)
include $(BUILD_PHONY_PACKAGE)

droidcore: dtbimage

endif
