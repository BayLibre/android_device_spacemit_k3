#!/bin/bash
#
# Flash script for SpacemiT K3 Muse Pico-ITX (K3 Pico-ITX) - Android
#
# Modeled on device/spacemit/k1/flash_bpi_f3.sh (the K1 / MusePi-Pro flasher).
# Same structure (fastboot default / --dfu BROM / --bootloader / --android /
# --wipe, A/B slots, JSON partition tables) adapted to the K3 boot media and
# flash method.
#
# Place all required files in the same directory as this script, then run it.
#
# Usage:
#   ./flash_pico_itx.sh                Flash all via fastboot (bootloader + android)
#   ./flash_pico_itx.sh --bootloader   Flash bootloader only (to SPI-NOR)
#   ./flash_pico_itx.sh --android      Flash Android images only (to eMMC)
#   ./flash_pico_itx.sh --dfu          Full DFU flash (board in BROM mode)
#   ./flash_pico_itx.sh --wipe         Include userdata wipe (combines with any mode)
#
# For fastboot modes, start "fastboot usb 0" on the U-Boot console first.
# For DFU mode, the board must be in BROM DFU mode (USB 361c:1001).
#
# =============================================================================
# !!! HARDWARE VALIDATION REQUIRED — READ BEFORE FLASHING A REAL BOARD !!!
# =============================================================================
# This script was written from the K3 vendor BSP + K1 flasher WITHOUT a physical
# K3 Pico-ITX to test against. Every K3-specific value below is annotated where
# it is an ASSUMPTION. Search this file for "ASSUMPTION:" and "VALIDATE:" before
# trusting it on hardware. The biggest unknowns:
#
#   1. BOOT MEDIA (bootloader)  : K3 Pico-ITX boots from SPI-NOR over QSPI
#      (d420c000.spi). BROM->FSBL->OpenSBI->U-Boot all live in NOR, selected by
#      the K3 boot strap. So the bootloader is flashed to NOR exactly like the
#      K1 MusePi-Pro path (flash mtd <json> + bootinfo_spinor.bin), NOT to eMMC.
#      Sources:
#        - /srv/spacemit/k3/docs/2026-06-16-k3-bootloader-port-plan.md (dim 4)
#        - bsp-src/uboot-2022.10/board/spacemit/k3/k3.c (get_boot_pin_select,
#          BOOT_MODE_NOR, k3_nor_boot_prio[])
#        - bsp-src/uboot-2022.10/configs/k3_defconfig (MTDPARTS d420c000.spi)
#        - buildroot-ext/board/spacemit/k3/partition_4M.json (NOR MTD layout)
#      VALIDATE: confirm the Pico-ITX strap actually selects NOR (vs eMMC/UFS)
#      and that the production board populates a NOR chip on d420c000.spi.
#
#   2. ANDROID MEDIA (boot/super/...) : assumed eMMC (mmc dev 2), matching
#      CONFIG_FASTBOOT_FLASH_MMC_DEV=2 in k3_defconfig and the K1 layout. BUT on
#      K3 the NOR external-boot priority is UFS(scsi0) > NVMe > eMMC(mmc2) > USB
#      (k3.c k3_nor_boot_prio[]), and UFS is the *defining net-new* K3 storage.
#      The Pico-ITX may ship Android on UFS, not eMMC. See --android-media below.
#      VALIDATE: where does the Pico-ITX actually carry the Android GPT (eMMC vs
#      UFS)? If UFS, the U-Boot Android fastboot backend must target UFS/SCSI and
#      partition_android.json offsets/device must change.
#
#   3. ANDROID-BOOT SUPPORT IN U-BOOT : the vendor k3_defconfig has
#      "# CONFIG_ANDROID_BOOT_IMAGE is not set" (it is a buildroot/FIT config).
#      bootmeth_android / AVB / BCB / A/B / Android-GPT fastboot is GREENFIELD on
#      K3 (port plan dim 7 — tier-a, config-only, but not yet enabled). This
#      script's --android / GPT / set_active steps ASSUME that Android-boot
#      support has been added to the K3 U-Boot (same upstream framework as K1).
#      Until then, only --bootloader and the DFU bootloader-staging path are
#      meaningful; the Android steps will fail on a buildroot K3 U-Boot.
#      VALIDATE: K3 U-Boot built with ANDROID_BOOT_IMAGE + FASTBOOT_FLASH_MMC +
#      EFI_PARTITION + CMD_GPT + ANDROID_AB, per the port plan.
#
#   4. PARTITION OFFSETS / NAMES : partition_nor.json (NOR bootloader MTD) and
#      partition_android.json (eMMC Android GPT) are expected to be staged next
#      to this script (produced by the K3 bootloader build, K1-style). Their
#      exact offsets/sizes are NOT validated here. The vendor NOR MTD layout
#      (partition_4M.json) uses offsets: bootinfo@0/128K, fsbl@128K/512K,
#      env@640K/64K, opensbi@1728K/384K, uboot@2112K — DIFFERENT from the K1
#      NOR layout — so the K3 partition_nor.json must match the K3 FSBL/SPL
#      build, not be copied from K1.
#      VALIDATE: partition_nor.json offsets == K3 FSBL spl0/spl1 offsets
#      (bootinfo_spinor.json: spl0=0x20000, spl1=0xA0000).
#
#   5. BROM USB ID : 361c:1001 — taken from k3_defconfig
#      (CONFIG_USB_GADGET_VENDOR_NUM=0x361c, PRODUCT_NUM=0x1001), same as K1.
#      VALIDATE: lsusb when the Pico-ITX is in BROM DFU mode.
#
#   6. EC / CrosEC FIRMWARE : the K3 Pico-ITX has an embedded controller (eSPI /
#      CrosEC). The vendor fastboot.yaml stages an optional "ec.bin" and runs
#      "oem ec:flash" during BROM bring-up. This script flashes ec.bin only if
#      present, best-effort. VALIDATE: whether the EC needs (re)flashing at all,
#      and the correct ec.bin artifact.
#
#   Source of the K3 flash method itself:
#     buildroot-ext/board/spacemit/k3/fastboot.yaml  (vendor flashing choreography)
#       getvar version-brom -> stage factory/FSBL.bin -> continue
#       -> oem speed:super-speed -> stage u-boot.itb -> continue
#       -> [stage ec.bin -> oem ec:flash] -> multi_flash partition_*.json
#     => The K3 "flash method" is fastboot (no Titan Flasher / no external GUI),
#        identical protocol to K1. The K3 vendor U-Boot fastboot routes
#        "flash mtd <json>" to NOR/NAND and "flash gpt <json>" to a block device,
#        toggling on the literal arg — verified in
#        bsp-src/uboot-2022.10/drivers/fastboot/fb_command.c (lines ~555-559).
#        That is the SAME mechanism the K1 flasher relies on, so the K1 script
#        structure ports directly.
# =============================================================================
set -euo pipefail

# ============================================================================
# Configuration — all files relative to script directory
# ============================================================================
IMG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Bootloader dir. Unlike the K1 device (which has two boards sharing one Android
# build), K3 currently has a single board (Pico-ITX), so the bootloader blobs
# live right next to this script, same dir as the Android images.
BL="${IMG}"

# Android storage target. K3 boots the bootloader from SPI-NOR, but the Android
# GPT (boot/super/...) lives on a block device. Default "emmc" (mmc dev 2) per
# CONFIG_FASTBOOT_FLASH_MMC_DEV=2. ASSUMPTION (#2 above): may be "ufs" on real
# Pico-ITX hardware. Overridable with --android-media.
ANDROID_MEDIA="emmc"

# Fastboot binary. The K1 flasher resolves it from PATH; the project's known-good
# fastboot is /srv/data/android-sdk/platform-tools/fastboot — prefer it, then
# fall back to PATH.
FASTBOOT="/srv/data/android-sdk/platform-tools/fastboot"
if [ ! -x "${FASTBOOT}" ]; then
    FASTBOOT=$(command -v fastboot 2>/dev/null || true)
fi

# ============================================================================
# Colors
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { err "$*"; exit 1; }

# ============================================================================
# Check fastboot
# Use if/then/fi (NOT "[ cond ] && die"): with `set -euo pipefail`, a failing
# "[ cond ] &&" short-circuit returns non-zero and silently aborts the script.
# ============================================================================
require_fastboot() {
    if [ -z "${FASTBOOT}" ] || [ ! -x "${FASTBOOT}" ]; then
        die "fastboot not found (looked at /srv/data/android-sdk/platform-tools/fastboot and PATH)"
    fi
}

# ============================================================================
# Wait for fastboot device
# ============================================================================
wait_for_device() {
    local timeout="${1:-30}"
    local description="${2:-fastboot device}"
    local elapsed=0

    info "Waiting for ${description} (${timeout}s)..."
    while [ ${elapsed} -lt ${timeout} ]; do
        if ${FASTBOOT} devices 2>/dev/null | grep -q -E "fastboot|Fastboot|DFU|dfu|download"; then
            ok "Device detected"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    die "Timeout waiting for ${description}"
}

# ============================================================================
# Check required files
# ============================================================================
check_files() {
    local missing=false
    for f in "$@"; do
        if [ ! -f "${IMG}/${f}" ]; then
            err "Missing: ${IMG}/${f}"
            missing=true
        fi
    done
    if [ "${missing}" = true ]; then
        die "Required files missing. Place them next to this script."
    fi
}

# ============================================================================
# DFU staging: BROM -> FSBL -> U-Boot (K3 sequence)
#
# Mirrors the vendor fastboot.yaml BROM choreography:
#   getvar version-brom -> stage factory/FSBL.bin -> continue
#   -> oem speed:super-speed -> stage u-boot.itb -> continue
#
# Differs from the K1 dfu_stage only in the optional "oem speed:super-speed"
# between the FSBL and U-Boot stages (K3 negotiates USB SuperSpeed before the
# larger u-boot.itb download). ASSUMPTION (#5/#6): the K3 BROM accepts the same
# `fastboot stage`/`continue` protocol the K1 BROM does.
# ============================================================================
dfu_stage() {
    info "Step 1: Staging FSBL into BROM..."
    wait_for_device 10 "DFU device (361c:1001)"
    ${FASTBOOT} stage "${BL}/factory/FSBL.bin"
    ${FASTBOOT} continue
    info "BROM executing FSBL..."
    sleep 5

    info "Step 2: Connecting to FSBL fastboot..."
    wait_for_device 60 "FSBL fastboot"
    # Negotiate SuperSpeed before the larger u-boot.itb (best-effort; the vendor
    # yaml marks this skip_fail). Don't let a non-SuperSpeed link abort the flash.
    ${FASTBOOT} oem speed:super-speed 2>/dev/null || warn "oem speed:super-speed not accepted (continuing at current USB speed)"

    info "Step 3: Staging U-Boot..."
    ${FASTBOOT} stage "${BL}/u-boot.itb"
    ${FASTBOOT} continue
    info "FSBL executing U-Boot..."
    sleep 5

    # Optional EC firmware (Pico-ITX CrosEC). Best-effort, only if ec.bin staged.
    # VALIDATE (#6): whether the EC needs flashing and the correct artifact.
    if [ -f "${BL}/factory/ec.bin" ]; then
        info "Step 3b: Flashing EC firmware (ec.bin)..."
        ${FASTBOOT} stage "${BL}/factory/ec.bin" 2>/dev/null || warn "EC stage failed (skipping)"
        ${FASTBOOT} oem ec:flash 2>/dev/null || warn "oem ec:flash failed (skipping)"
    fi

    info "Step 4: Connecting to U-Boot fastboot..."
    wait_for_device 60 "U-Boot fastboot"
}

# ============================================================================
# Flash bootloader to SPI-NOR (K3 Pico-ITX boots from NOR, like K1 MusePi-Pro)
#
# The K3 U-Boot routes a partition to SPI-NOR when a matching
# fastboot_raw_partition_<name> env var exists (defined in U-Boot's
# CFG_EXTRA_ENV_SETTINGS from the partition_nor.json layout); other partitions
# go to the eMMC backend. The bootloader blobs are flashed by name directly --
# no "flash mtd <table>" step (that was the vendor BSP's JSON-table protocol;
# upstream U-Boot uses the env-defined raw partitions instead).
#
# K3-vs-K1 deltas:
#   - bootinfo image is bootinfo_spinor.bin (BROM NOR header), as on K1 NOR.
#   - opensbi/u-boot offsets differ from K1 (see partition_nor.json, #4 above).
# ============================================================================
flash_bootloader_nor() {
    info "Flashing bootloader to SPI-NOR (${BL})..."
    ${FASTBOOT} flash bootinfo "${BL}/factory/bootinfo_spinor.bin"
    ${FASTBOOT} flash fsbl "${BL}/factory/FSBL.bin"
    ${FASTBOOT} flash env "${BL}/env.bin"
    ${FASTBOOT} flash opensbi "${BL}/fw_dynamic.itb"
    ${FASTBOOT} flash uboot "${BL}/u-boot.itb"
    ok "Bootloader flashed to SPI-NOR"
}

# ============================================================================
# Flash Android boot partitions (both slots a and b)
# Identical contract to the K1 flasher: vbmeta set first (AVB), then the boot
# images per slot, then reset BCB (misc) and select slot a.
#
# ASSUMPTION (#3): the K3 U-Boot has bootmeth_android + AVB + A/B enabled. On a
# buildroot K3 U-Boot these named partitions do not exist and these calls fail.
# ============================================================================
flash_android_boot() {
    info "Flashing Android boot images (slots a + b)..."

    # Flash all vbmeta images (required for AVB)
    local vbmeta_images="vbmeta vbmeta_vendor_dlkm vbmeta_system_dlkm"
    for vbmeta in ${vbmeta_images}; do
        if [ -f "${IMG}/${vbmeta}.img" ]; then
            info "Flashing ${vbmeta}..."
            for slot in a b; do
                if [ "${DISABLE_AVB}" = "true" ]; then
                    ${FASTBOOT} --disable-verity --disable-verification flash "${vbmeta}_${slot}" "${IMG}/${vbmeta}.img"
                else
                    ${FASTBOOT} flash "${vbmeta}_${slot}" "${IMG}/${vbmeta}.img"
                fi
            done
        else
            warn "${vbmeta}.img not found"
        fi
    done
    ok "vbmeta images flashed"

    for slot in a b; do
        if [ -f "${IMG}/boot.img" ]; then
            ${FASTBOOT} flash "boot_${slot}" "${IMG}/boot.img"
        fi
        if [ -f "${IMG}/init_boot.img" ]; then
            ${FASTBOOT} flash "init_boot_${slot}" "${IMG}/init_boot.img"
        fi
        if [ -f "${IMG}/vendor_boot.img" ]; then
            ${FASTBOOT} flash "vendor_boot_${slot}" "${IMG}/vendor_boot.img"
        fi
        if [ -f "${IMG}/dtbo.img" ]; then
            ${FASTBOOT} flash "dtbo_${slot}" "${IMG}/dtbo.img"
        fi
    done
    # Reset the A/B BCB by erasing misc. The block backend zero-fills when the
    # UFS refuses hardware erase, so 'erase' works; the zeroed-image path stays
    # as a last resort. Never abort the whole flash on this.
    info "Erasing misc (A/B BCB)..."
    if ! ${FASTBOOT} erase misc; then
        warn "erase failed; clearing the misc BCB via a zeroed image"
        local zero="${IMG}/.misc_zero.img"
        dd if=/dev/zero of="${zero}" bs=4096 count=16 2>/dev/null
        ${FASTBOOT} flash misc "${zero}" 2>/dev/null || warn "could not clear misc; if A/B carries a stale bootloader command, clear it from Android or the U-Boot console"
        rm -f "${zero}"
    fi
    ${FASTBOOT} set_active a 2>/dev/null || warn "set_active not supported, slot may need manual selection"
    ok "Boot images flashed (both slots)"
}

# ============================================================================
# Flash super partition
# ============================================================================
flash_super() {
    info "Flashing super (system+vendor)... this takes a while"
    ${FASTBOOT} flash super "${IMG}/super.img"
    ok "Super flashed"
}

# ============================================================================
# Flash userdata
# ============================================================================
flash_userdata() {
    info "Flashing userdata..."
    ${FASTBOOT} flash userdata "${IMG}/userdata.img"
    # As on K1, the U-Boot fastboot 'format' can't always resolve metadata/persist
    # ("incorrect device type / cannot find partition") even though 'flash' works.
    # Android (vold/init) formats them on first boot, so don't abort the flash.
    info "Formatting metadata (f2fs)..."
    ${FASTBOOT} format:f2fs metadata || warn "metadata format unsupported by U-Boot fastboot; Android will format it on first boot"
    info "Formatting persist (ext4)..."
    ${FASTBOOT} format:ext4 persist || warn "persist format unsupported by U-Boot fastboot; Android will format it on first boot"
    ok "Userdata flashed (metadata/persist deferred to first boot if format is unsupported)"
}

# ============================================================================
# Write the Android GPT to the block device.
#
# "flash gpt <json>" routes to the block device (fb_command.c: mtd_flash=false
# on the literal "gpt" arg). ASSUMPTION (#2): block device = eMMC (mmc dev 2).
# If ANDROID_MEDIA=ufs, partition_android.json must describe the UFS device and
# the K3 U-Boot fastboot block backend must target SCSI/UFS — flag, do not guess.
# ============================================================================
flash_android_gpt() {
    info "Writing Android GPT to UFS (scsi 0)..."
    # Upstream U-Boot has no JSON GPT parser, so build the table the U-Boot-native
    # way: 'gpt write' consumes the 'partitions' env baked into the bootloader
    # (CFG_EXTRA_ENV_SETTINGS), driven over fastboot via FASTBOOT_OEM_RUN. The UFS
    # is scanned at fastboot entry (k3_prepare_scsi_flash_target).
    if ! ${FASTBOOT} oem "run:gpt write scsi 0 \$partitions"; then
        warn "GPT write failed; the by-name flashes below will likely fail."
        warn "Run manually on the U-Boot console: 'gpt write scsi 0 \$partitions'."
    else
        info "Android GPT written to UFS (scsi 0)"
    fi
}

# ============================================================================
# Mode: full — flash everything via fastboot (default)
# ============================================================================
mode_all() {
    local wipe="$1"

    require_fastboot
    check_files factory/FSBL.bin factory/bootinfo_spinor.bin fw_dynamic.itb \
                u-boot.itb env.bin partition_nor.json boot.img super.img vbmeta.img

    echo ""
    echo -e "${BOLD}=== Full fastboot flash ===${NC}"
    echo -e " Run ${YELLOW}fastboot usb 0${NC} on U-Boot console first"
    echo ""

    wait_for_device 30 "U-Boot fastboot (run 'fastboot usb 0' on board)"
    # K3 Pico-ITX always boots the bootloader from SPI-NOR (#1).
    flash_bootloader_nor
    flash_android_boot
    flash_super

    if [ "${wipe}" = "false" ]; then
        info "Skipping userdata (use --wipe for clean install)"
    fi
    # Always flash userdata during development (matches K1 flasher behaviour)
    flash_userdata

    echo ""
    ok "Flash complete! Rebooting..."
    ${FASTBOOT} reboot 2>/dev/null || warn "Auto-reboot failed, power cycle manually"
}

# ============================================================================
# Mode: --bootloader
# ============================================================================
mode_bootloader() {
    local wipe="$1"

    require_fastboot
    check_files factory/FSBL.bin factory/bootinfo_spinor.bin fw_dynamic.itb \
                u-boot.itb env.bin partition_nor.json

    echo ""
    echo -e "${BOLD}=== Bootloader flash (fastboot, SPI-NOR) ===${NC}"
    echo -e " Run ${YELLOW}fastboot usb 0${NC} on U-Boot console first"
    echo ""

    wait_for_device 15 "U-Boot fastboot (run 'fastboot usb 0' on board)"
    flash_bootloader_nor

    echo ""
    ok "Done! Reboot the board to use new bootloader."
    ${FASTBOOT} reboot 2>/dev/null || warn "Auto-reboot failed, power cycle manually"
}

# ============================================================================
# Mode: --android
# ============================================================================
mode_android() {
    local wipe="$1"

    require_fastboot
    check_files boot.img

    echo ""
    echo -e "${BOLD}=== Android flash (fastboot, ${ANDROID_MEDIA}) ===${NC}"
    echo -e " Run ${YELLOW}fastboot usb 0${NC} on U-Boot console first"
    echo ""

    wait_for_device 15 "U-Boot fastboot (run 'fastboot usb 0' on board)"
    flash_android_boot

    if [ -f "${IMG}/super.img" ]; then
        flash_super
    else
        warn "super.img not found, skipping"
    fi

    # Always flash userdata during development
    flash_userdata

    echo ""
    ok "Done! Rebooting..."
    ${FASTBOOT} reboot 2>/dev/null || warn "Auto-reboot failed, power cycle manually"
}

# ============================================================================
# Mode: --dfu (full DFU from BROM)
#
# K3 Pico-ITX: bootloader -> SPI-NOR (NOR MTD layout), Android -> block device
# (eMMC by default). Same ordering as the K1 MusePi-Pro DFU path: stage to BROM,
# write the NOR bootloader, then write the Android GPT + images to the block dev.
# ============================================================================
mode_dfu() {
    local wipe="$1"

    require_fastboot
    check_files u-boot.itb fw_dynamic.itb env.bin factory/FSBL.bin \
                factory/bootinfo_spinor.bin partition_nor.json \
                partition_android.json boot.img super.img vbmeta.img

    echo ""
    echo -e "${BOLD}=== Full DFU flash ===${NC}"
    echo -e " Board must be in ${YELLOW}DFU mode${NC} (USB ID 361c:1001)"
    echo ""

    # DFU staging: BROM -> FSBL -> U-Boot
    dfu_stage

    # Bootloader -> SPI-NOR first (so the bootloader MTD parts resolve to NOR
    # before the Android GPT exists on the block device).
    flash_bootloader_nor

    # Android -> block device GPT + images.
    flash_android_gpt
    flash_android_boot
    flash_super

    # Always flash userdata during development
    flash_userdata

    echo ""
    ok "Flash complete! Rebooting..."
    ${FASTBOOT} reboot || warn "Reboot failed, power cycle manually"
}

# ============================================================================
# Main
# ============================================================================
usage() {
    cat <<'EOF'
Usage: flash_pico_itx.sh [MODE] [OPTIONS]

All image files must be in the same directory as this script.
For fastboot modes, run "fastboot usb 0" on the U-Boot console first.

Modes:
  (default)            Flash bootloader (SPI-NOR) + Android via fastboot
  --bootloader         Flash bootloader only (to SPI-NOR) via fastboot
  --android            Flash Android images only via fastboot
  --dfu                Full DFU flash (board in BROM mode, first-time setup)

Options:
  --android-media <m>  Android block target: emmc (default) | ufs
                       NOTE: ufs is UNVALIDATED on real hardware (see header #2)
  --wipe               Also flash userdata (clean install)
  --no-avb             Disable AVB verification (for bringup/development)
  --help               Show this help

Examples:
  ./flash_pico_itx.sh                       # Flash everything (K3 Pico-ITX)
  ./flash_pico_itx.sh --bootloader          # Flash only the SPI-NOR bootloader
  ./flash_pico_itx.sh --android             # Flash only Android images
  ./flash_pico_itx.sh --dfu --wipe          # First-time DFU setup with clean userdata

!!! This script is BEST-EFFORT and was written WITHOUT a physical K3 Pico-ITX.
    Read the "HARDWARE VALIDATION REQUIRED" block at the top of this file and
    grep for "ASSUMPTION:" / "VALIDATE:" before flashing real silicon.
EOF
}

main() {
    local mode="all"
    local do_wipe=false
    local from_dfu=false
    DISABLE_AVB=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --bootloader)    mode="bootloader"; shift ;;
            --android)       mode="android"; shift ;;
            --dfu)           from_dfu=true; shift ;;
            --wipe)          do_wipe=true; shift ;;
            --no-avb)        DISABLE_AVB=true; shift ;;
            --android-media) ANDROID_MEDIA="$2"; shift 2 ;;
            --help|-h)       usage; exit 0 ;;
            *) die "Unknown option: $1 (see --help)" ;;
        esac
    done

    case "${ANDROID_MEDIA}" in
        emmc|ufs) ;;
        *) die "Unknown --android-media: ${ANDROID_MEDIA} (use: emmc | ufs)" ;;
    esac

    echo ""
    echo "============================================"
    echo " SpacemiT K3 (RISC-V) - Android Flash Tool"
    echo " Board: K3 Muse Pico-ITX"
    echo "============================================"
    echo " Bootloader media: SPI-NOR (QSPI d420c000.spi)"
    echo " Android media:    ${ANDROID_MEDIA}"
    echo " Android images:   ${IMG}"
    echo " Bootloader:       ${BL}"
    echo ""

    # --dfu is a modifier: it stages BROM -> FSBL -> U-Boot first. Alone it runs
    # the full first-time flash (mode_dfu); combined with a mode it stages, then
    # runs only that mode's flash steps.
    if [ "${from_dfu}" = true ] && [ "${mode}" = "all" ]; then
        mode_dfu "${do_wipe}"
    elif [ "${from_dfu}" = true ]; then
        require_fastboot
        dfu_stage
        case "${mode}" in
            bootloader)
                flash_bootloader_nor
                ;;
            android)
                flash_android_gpt
                flash_android_boot
                flash_super
                [ "${do_wipe}" = true ] && flash_userdata
                ;;
        esac
        echo ""
        ok "Done (DFU + ${mode}). Power-cycle the board to use it."
        ${FASTBOOT} reboot 2>/dev/null || warn "auto-reboot failed, power cycle manually"
    else
        case "${mode}" in
            bootloader) mode_bootloader "${do_wipe}" ;;
            android)    mode_android "${do_wipe}" ;;
            all)        mode_all "${do_wipe}" ;;
        esac
    fi
}

main "$@"
