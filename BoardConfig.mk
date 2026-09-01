#
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit common configuration
include device/spacemit/common/BoardConfigCommon.mk

# Platform
TARGET_BOARD_PLATFORM := k3
TARGET_BOOTLOADER_BOARD_NAME := k3

# CPU: SpacemiT X100 (RVA23). No dedicated soong arch variant exists yet, so
# reuse the "x60" variant for now — its RVA22 baseline runs on the X100 (RVA23
# is a superset). An "x100" variant (RVA23 -mcpu/-march) is a phase-2 build/soong
# optimization.
TARGET_ARCH_VARIANT := x100

# All 8 X100 harts are brought up. Idle is bare WFI with cpuidle off (exact
# vendor parity: the vendor defconfig has no CPU_IDLE). A shallow WFI hart is
# woken by its own S-mode sstc timer and by IMSIC IPIs; it must be kept OUT of
# the PMU power-collapsed state (where only an M-mode MSIP/PMU event can wake
# it) -- OpenSBI does that by de-voting the per-core PMU power-down in
# cold_boot_allowed. No irqchip.riscv_imsic_noipi: the kernel uses the vendor's
# direct S-mode IMSIC IPI path.
#
# DIAGNOSTIC (temporary): panic=5 confirmed the ~16s "silent hang" is actually a
# kernel PANIC (the board reboots), but it printed nothing -- the real ttyS0
# (8250, IRQ-driven) does not flush during panic. keep_bootcon keeps the polling
# earlycon (uart8250) registered past 2.4s so console_flush_on_panic() can print
# the oops/backtrace over it; ignore_loglevel prints everything. panic=5 dropped
# so the panic HALTS with the backtrace frozen on screen (no reboot, no /data
# corruption loop). Remove all once the panic is root-caused.
# printk.devkmsg=on: the default /dev/kmsg ratelimit (10 writes / 5s per fd)
# silently drops the KMDBG instrumentation lines from the keymint HAL exactly
# around the vold keygen burst — proven by both "exit len=" lines being
# truncated at the 10th write. Disable it so the hang diagnosis is complete.
# Console verbosity: default loglevel (debug flags keep_bootcon/ignore_loglevel/
# printk.devkmsg removed now that the freeze is root-caused).

# Bring-up only: ttyS0 is IRQ-driven and does not flush during a panic, so an
# oops prints nothing once the console has handed over. Keeping the polling
# earlycon registered lets console_flush_on_panic() get the backtrace out. The
# cost is every line appearing twice, both consoles driving the same UART.
# Drop this once the K3 boots without panicking.
BOARD_KERNEL_CMDLINE += keep_bootcon

# Kernel — the SHARED common K1/K3 kernel; the K3 board DTB is k3-pico-itx.dtb
TARGET_KERNEL_USE ?= mainline
KERNEL_MODULES_PATH := device/spacemit/kernel/$(TARGET_KERNEL_USE)
TARGET_PREBUILT_KERNEL := $(KERNEL_MODULES_PATH)/Image

# Kernel modules — force the CCU core first (spacemit-ccu.ko exports the symbols
# that spacemit-ccu-k3.ko links against), same split as K1.
#
# ufs-spacemit.ko (CONFIG_SCSI_UFS_SPACEMIT_K3) is the SpacemiT host glue for the
# ufshc@c0e00000 controller. The Pico-ITX has no eMMC — its only storage is UFS —
# so this module MUST probe before the first-stage mount, i.e. it has to live in
# the vendor_boot ramdisk and load early. The UFS/SCSI core is builtin; only this
# host glue is a module. It is force-ordered right after the clocks (the UFS
# controller's clocks come from spacemit-ccu*). Listed via $(wildcard ...) so the
# build stays green until the kernel build publishes the .ko into the ramdisk dir
# (kernel-side: enable CONFIG_SCSI_UFS_SPACEMIT_K3=m and add it to the ramdisk
# module set + initramfs/modules.load).
BOARD_VENDOR_RAMDISK_KERNEL_MODULES := $(wildcard $(KERNEL_MODULES_PATH)/ramdisk/*.ko)
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := \
    $(KERNEL_MODULES_PATH)/ramdisk/spacemit-ccu.ko \
    $(wildcard $(KERNEL_MODULES_PATH)/ramdisk/ufs-spacemit.ko) \
    $(filter-out %/spacemit-ccu.ko %/ufs-spacemit.ko %/spacemit-drm.ko %/spacemit_hdmi.ko,$(BOARD_VENDOR_RAMDISK_KERNEL_MODULES))

# The shared K1/K3 kernel builds both display stacks. On K3 the K1 DRM drivers
# (spacemit-drm.ko + spacemit_hdmi.ko) must not load: they grab the "display"
# class and the "spacemit-drm-drv" platform driver first, so the K3 driver
# (spacemit_drm_k3 / inno-dp, in vendor_dlkm) aborts with -EEXIST. They are
# excluded from the first-stage modules.load above rather than kernel
# module_blacklist= (which makes first-stage finit_module fail -EPERM and reboots
# init to the bootloader). Ramdisk-only modules never loaded first-stage are
# never loaded at all, so the K3 display pipeline wins.

BOARD_VENDOR_KERNEL_MODULES := $(wildcard $(KERNEL_MODULES_PATH)/vendor_dlkm/*.ko)
BOARD_VENDOR_KERNEL_MODULES_LOAD := $(BOARD_VENDOR_KERNEL_MODULES)
BOARD_SYSTEM_KERNEL_MODULES := $(wildcard $(KERNEL_MODULES_PATH)/system_dlkm/*.ko)
BOARD_SYSTEM_KERNEL_MODULES_LOAD := $(BOARD_SYSTEM_KERNEL_MODULES)

# Bootconfig
BOARD_BOOTCONFIG += androidboot.hardware=k3
# Storage = UFS (the Pico-ITX has no eMMC; UFS 2.2 is the only storage).
# Path derived from k3.dtsi: the controller node is
#   soc: soc { ...; ufshc: ufshc@c0e00000 { compatible = "spacemit,k3-ufshcd"; ... } }
# i.e. a DIRECT child of /soc (no storage-bus wrapper, unlike K1's eMMC). Linux
# names the platform device from the node base name -> "c0e00000.ufshc", so the
# sysfs path is /devices/platform/soc/c0e00000.ufshc and the boot_devices token
# is soc/c0e00000.ufshc. First-stage init walks this controller down to its SCSI
# block device and builds /dev/block/platform/<this>/by-name/* from the GPT.
# NEEDS-BOARD-CONFIRMATION: verify against the live sysfs node name once a board
# boots — if the kernel renames the node (e.g. ufs@c0e00000) the suffix changes.
BOARD_BOOTCONFIG += androidboot.boot_devices=soc/c0e00000.ufshc
BOARD_BOOTCONFIG += androidboot.fstab_suffix=k3
BOARD_BOOTCONFIG += androidboot.vendor.apex.com.android.hardware.keymint=com.android.hardware.keymint.rust_nonsecure
BOARD_BOOTCONFIG += androidboot.vendor.apex.com.android.hardware.gatekeeper=com.android.hardware.gatekeeper.nonsecure
BOARD_BOOTCONFIG += androidboot.selinux=permissive

# Partition sizes (mirror the K1 dynamic-partition scheme inherited from common)
BOARD_SUPER_PARTITION_SIZE := 4831838208
BOARD_SPACEMIT_DYNAMIC_PARTITIONS_SIZE := 2411724800
BOARD_USERDATAIMAGE_PARTITION_SIZE := 10662837248

# WiFi — RTL8852BE on PCIe, mainline rtw89 driver (nl80211).
# realtek makes libwifi_hal absorb libwifi-hal-rtk, now in-tree at
# hardware/realtek/wlan/wifi_hal. Leaving this unset instead selects
# libwifi-hal-fallback, whose vendor entry points are all stubs; the framework
# still works over plain nl80211 through wificond and wpa_supplicant, so the
# fallback is a usable configuration if the vendor HAL ever gets in the way.
# Caveat worth knowing: that HAL issues Realtek private nl80211 vendor commands
# meant for their out-of-tree driver, while this board runs mainline rtw89. Base
# connectivity does not depend on them, but the vendor features they back —
# gscan, RTT, link layer stats, the ring-buffer logger — can be expected to fail
# at runtime rather than at build time.
BOARD_WLAN_DEVICE := realtek
# Install the supplicant's init service. Without this the wpa_supplicant binary
# and its VINTF manifest ship, but nothing declares the init service, so the
# AIDL interface is advertised with no process behind it and the framework fails
# with "Failed to get internal ISupplicantStaIfaceHal instance".
WIFI_HIDL_UNIFIED_SUPPLICANT_SERVICE_RC_ENTRY := true
WPA_SUPPLICANT_VERSION := VER_0_8_X
BOARD_WPA_SUPPLICANT_DRIVER := NL80211
BOARD_HOSTAPD_DRIVER := NL80211

# Bluetooth — RTL8852B on USB (btusb + btrtl). Unlike K1 (UART transport,
# rtk_hciattach on /dev/ttyS1), btusb enumerates the controller as a standard
# USB HCI, so the AOSP default Bluetooth HAL drives it directly with no vendor
# UART transport. bdroid_buildcfg.h still carries the board name / class-of-dev.
BOARD_HAVE_BLUETOOTH := true
BOARD_BLUETOOTH_BDROID_BUILDCFG_INCLUDE_DIR := device/spacemit/k3/bluetooth

# SELinux
BOARD_VENDOR_SEPOLICY_DIRS += device/spacemit/k3/sepolicy/vendor

# Recovery
TARGET_RECOVERY_FSTAB_GENRULE := gen_fstab_k3

# VINTF
DEVICE_MANIFEST_FILE := device/spacemit/k3/manifest.xml
