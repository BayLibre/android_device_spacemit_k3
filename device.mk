#
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit common (SoC-agnostic HALs, mesa GPU stack, A/B, codecs, webview, ...)
$(call inherit-product, device/spacemit/common/device-common.mk)

# Vendor firmware (WiFi rtw89 + Bluetooth rtl_bt USB blobs)
$(call inherit-product, vendor/spacemit/k3/k3.mk)

# Platform
PRODUCT_PLATFORM := k3

# Soong namespaces for the shared Mesa GPU stack pulled by common.
# common/device-common.mk requires the mesa prebuilts (libGLES_mesa, vulkan.mesa,
# libgbm_mesa, *_dri, ...) and libgbm_mesa_wrapper, but those modules live in
# namespaces that are NOT auto-imported (Soong namespaces are non-recursive, so
# importing device/spacemit/k1 does not cover device/spacemit/k1/mesa). Without
# these, the modules are silently dropped and the gbm_mesa gralloc backend /
# Mesa EGL+Vulkan are absent from /vendor.
PRODUCT_SOONG_NAMESPACES += \
    device/spacemit/k1/mesa \
    external/minigbm/gbm_mesa_driver

# Kernel (shared common K1/K3 build)
TARGET_KERNEL_USE ?= mainline
LOCAL_KERNEL := device/spacemit/kernel/$(TARGET_KERNEL_USE)/Image
PRODUCT_COPY_FILES += \
    $(LOCAL_KERNEL):kernel

# Properties
# sys.usb.configfs=1: use the modern configfs USB gadget (/config/usb_gadget)
# instead of the legacy android_usb driver, which does not exist in the mainline
# kernel. Without it the gadget is never created and ADB has no UDC to bind.
# ro.surface_flinger.protected_contents=false: the PowerVR/Mesa Vulkan stack has
# no protected (secure/DRM) memory support; without this SurfaceFlinger tries to
# build a protected-content RenderEngine, fails, and aborts (bad_function_call).
PRODUCT_PROPERTY_OVERRIDES += \
    ro.hardware.gralloc=minigbm \
    ro.sf.lcd_density=240 \
    sys.usb.configfs=1 \
    ro.surface_flinger.protected_contents=false \
    config.disable_renderscript=true

# Drop android.renderscript.* from the Zygote preload list. RenderScript is
# deprecated (API 31) and librs_jni.so is not built on RISC-V, so preloading
# android.renderscript.Element throws a fatal RSRuntimeException in
# ZygoteInit.main -> Zygote crash-loops and system_server never forks (no
# boot_completed). The file is the upstream preloaded-classes minus those
# entries (mirrors the K1 board).
PRODUCT_COPY_FILES += \
    device/spacemit/k3/preloaded-classes:system/etc/preloaded-classes

# On-board speaker audio: the ES8326 codec on the secure TWSI3 bus, which ALSA
# enumerates as card "sndes8326". Select it by name -- card numbering is not
# stable, a USB webcam readily takes index 0 -- and keep the index only as a
# fallback for when the name lookup fails.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.vendor.audio.primary.card_name=sndes8326 \
    ro.vendor.audio.primary.card=1 \
    ro.vendor.audio.primary.device=0

# Audio policy config. The primary module must exist at all costs: without it
# the audio HAL exposes no IModule/default, AudioFlinger dies in a loop
# (AudioService.onAudioServerDied) and boot stalls at StartAudioService.
PRODUCT_COPY_FILES += \
    device/spacemit/k3/audio/audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_configuration.xml \
    device/spacemit/k3/audio/primary_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/primary_audio_policy_configuration.xml

# ============================================================
# Per-board bits (each SoC owns these; common stays generic)
# ============================================================
# Fstab
PRODUCT_PACKAGES += \
    fstab.k3 \
    fstab.k3.vendor_ramdisk

# DRM/KMS test tool for display bring-up: modetest drives a dumb linear
# buffer straight to the kernel DPU, bypassing SurfaceFlinger/gralloc/GPU.
PRODUCT_PACKAGES += \
    modetest

# Init / ueventd. init.k3.usb.rc creates the configfs USB gadget skeleton
# (g1 + ffs.adb + functionfs mounts) that init.usb.configfs.rc and the gadget
# HAL bind on top of; without it ADB has no UDC to bind (mirrors the K1 board).
PRODUCT_COPY_FILES += \
    device/spacemit/k3/init.k3.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/hw/init.k3.rc \
    device/spacemit/k3/init.k3.usb.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/init.k3.usb.rc \
    device/spacemit/k3/ueventd.k3.rc:$(TARGET_COPY_OUT_VENDOR)/etc/ueventd.rc

# ============================================================
# WiFi (RTL8852BE / rtw89 PCIe) + Bluetooth (RTL8852B / btusb USB)
# ============================================================
# The WiFi HAL and the supplicant are not pulled in by the base product, so
# without these the framework registers wlan0 and then fails to bring it up:
# "Failed to get internal ISupplicantStaIfaceHal instance" followed by
# "Failed to start supplicant" and "ClientModeManager start failed".
# The kernel side needs nothing: rtw89 loads its firmware and registers a
# standard nl80211 netdev on its own.
PRODUCT_PACKAGES += \
    android.hardware.wifi-service \
    wpa_supplicant \
    wpa_cli

# Declare the features, otherwise the framework keeps WiFi greyed out even with
# the HAL present.
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.wifi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.xml \
    frameworks/native/data/etc/android.hardware.wifi.direct.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.direct.xml

PRODUCT_VENDOR_PROPERTIES += \
    wifi.interface=wlan0

# WiFi supplicant config, read from /vendor/etc/wifi by wpa_supplicant. The
# rtw89 wlan netdev is a standard nl80211 interface, so no driver-specific
# overlay beyond disable_scan_offload.
PRODUCT_COPY_FILES += \
    device/spacemit/k3/wifi/wpa_supplicant.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant.conf \
    device/spacemit/k3/wifi/wpa_supplicant_overlay.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant_overlay.conf \
    device/spacemit/k3/wifi/p2p_supplicant_overlay.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/p2p_supplicant_overlay.conf

# Bluetooth HAL. The generic AOSP service is the right one for this controller:
# BluetoothHci::initialize() tries NetBluetoothMgmt::openHci() first, which is an
# AF_BLUETOOTH / HCI_CHANNEL_USER socket onto the kernel Bluetooth stack, and only
# falls back to opening a char device as an H4 UART. btusb registers the RTL8852B
# in that stack, so the socket path is taken and no vendor transport is involved.
# The service ships its own init .rc and VINTF fragment, so nothing else is needed.
PRODUCT_PACKAGES += \
    android.hardware.bluetooth-service.default

# Declare the features, otherwise the framework keeps Bluetooth unavailable even
# with the HAL running.
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.bluetooth.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth.xml \
    frameworks/native/data/etc/android.hardware.bluetooth_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth_le.xml

# Bluetooth vendor config. btusb is a self-contained USB HCI (no UART vendor
# transport), so this file carries no transport keys; it is copied only for
# parity / documentation. btrtl loads /vendor/firmware/rtl_bt/rtl8852bu_*.bin
# itself.
PRODUCT_COPY_FILES += \
    device/spacemit/k3/bluetooth/bt_vendor.conf:$(TARGET_COPY_OUT_VENDOR)/etc/bluetooth/bt_vendor.conf

# ============================================================
# GPU firmware (open-source drm/imagination / DRM_POWERVR)
# ============================================================
# The K3 GPU is PowerVR BXM-4-64 = BVNC 36.56.104.183 (distinct from the K1's
# BXE-2-32 / 36.29.52.182 — confirmed via the SpacemiT graphics doc + the BSP's
# two GPU firmwares). Open-source firmware fetched from the Imagination
# linux-firmware repo (gitlab.freedesktop.org/imagination/linux-firmware,
# powervr branch) — the open-source blob, distinct from the BSP's closed-DDK
# rgx.fw.*. The open-source drm/imagination driver loads it from /vendor/firmware.
PRODUCT_COPY_FILES += \
    device/spacemit/k3/firmware/powervr/rogue_36.56.104.183_v1.fw:$(TARGET_COPY_OUT_VENDOR)/firmware/powervr/rogue_36.56.104.183_v1.fw

# ============================================================
# External USB camera support
# ============================================================
# The K3 has no on-board camera; the only sensor path is a UVC device on one of
# the USB host ports (usb3_portd is the host-only Type-A). uvcvideo is built in
# (CONFIG_USB_VIDEO_CLASS=y), ueventd.k3.rc already labels /dev/video* as
# media:camera, and manifest.xml already declares ICameraProvider/external/0, so
# only the service and its config are missing.
#
# android.hardware.usb.host.xml is not listed here: device-common.mk already
# copies it for every SpaceMiT board.
PRODUCT_PACKAGES += \
    android.hardware.camera.provider-V1-external-service

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/external_camera_config.xml:$(TARGET_COPY_OUT_VENDOR)/etc/external_camera_config.xml \
    frameworks/native/data/etc/android.hardware.camera.external.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.external.xml
