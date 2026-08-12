#
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base.mk)
$(call inherit-product, device/spacemit/k3/device.mk)

PRODUCT_NAME := aosp_k3_pico_itx
PRODUCT_DEVICE := k3
PRODUCT_BRAND := SpacemiT
PRODUCT_MODEL := SpacemiT K3 Pico-ITX
PRODUCT_MANUFACTURER := SpacemiT
