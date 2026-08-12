# SpacemiT K3 (RISC-V) — Android device support

This directory is the AOSP device config for the **SpacemiT K3** SoC
(`spacemit,x100`; 8× out-of-order RVA23 cores, RVV/RVH, A100 NPU, PowerVR
BXM-4-64 GPU, riscv64). It targets the **Muse Pico-ITX** board.

The K3 shares **one common kernel with the K1** (see "Kernel" below): a single
GKI-style `Image` + per-board DTBs + a union module set. SoC drivers bind by
device-tree `compatible`, so K1 and K3 coexist in the same tree with no
regression to either.

| Board | SoC | `compatible` | Bootloader media | Android media |
|---|---|---|---|---|
| **Muse Pico-ITX** | K3 / x100 | `spacemit,k3-pico-itx`, `spacemit,k3` | **SPI-NOR** | **UFS 2.2** |

> The board boots its bootloader from **SPI-NOR**, then Android from **UFS**
> (UFS 2.2, 128/256 GB — there is no eMMC). The UFS user LU carries the GPT;
> the bootloader lives on the NOR. See "Storage" below.

## One device, one product

The device is `k3`; the lunch product lives in `k3_pico_itx/`:

- `aosp_k3_pico_itx` — `lunch aosp_k3_pico_itx-trunk_staging-userdebug`

`device/spacemit/k3/device.mk` inherits `device/spacemit/common` (SoC-agnostic
HALs, the Mesa GPU stack, A/B, codecs, webview, …) and adds the K3-specific
fstab, init, firmware, and storage/WiFi/BT wiring.

## Kernel: one common K1 + K3 build

Both SoCs build from the **same kleaf target** `spacemit_k1x` in
`devices/spacemit/spacemit_soc/` (this directory was historically named
`bananapi_f3/`; it was renamed because it is no longer K1/BPI-F3-specific —
it is the common SpacemiT SoC kernel). DTBs emitted from
`common/arch/riscv/boot/dts/spacemit/`:

- `k1-bananapi-f3.dtb`, `k1-musepi-pro.dtb` (K1 boards)
- `k3-pico-itx.dtb` (this board)

Build / re-stage the kernel prebuilt:

```sh
cd <kernel>
./tools/bazel run --config=spacemit_k1x \
    //devices/spacemit/spacemit_soc:spacemit_k1x_dist -- \
    --destdir=<aosp>/device/spacemit/kernel/<version>
```

`<version>` is the directory `TARGET_KERNEL_USE` names — `mainline` (default)
or `6.18`, the latter built from the `kernel-6.18/` tree. K1 and K3 share one
kernel, so there is one drop zone per version and none per SoC.

The config fragment is `devices/spacemit/spacemit_soc/spacemit_k1x.fragment`
(K3 options are gated/added there; K1 options are untouched).

## Functional bring-up status

All peripherals below are **ported, build-GREEN, and folded into the flashable
image set**. Hardware validation (probe, scan-out, link-training, enumeration)
is pending the real board.

| Function | Kernel | Firmware | Notes |
|---|---|---|---|
| **Display** | `spacemit-drm-k3.ko` (DPU saturn) + `spacemit_inno_dp.ko` (DP/eDP) | — | eDP 40-pin (2.5K) + USB-C DP (4K, DP-Alt-Mode). K3-gated, separate from K1 `spacemit-drm.ko`. |
| **GPU** | upstream **open-source** `drm/imagination` (`DRM_POWERVR`); BVNC **36.56.104.183** (BXM-4-64) | `powervr/rogue_36.56.104.183_v1.fw` | userspace = Mesa (≥26.1) `powervr_dri.so`. Firmware from the Imagination linux-firmware repo. |
| **USB** | `dwc3` + `phy-k3-usb2`/`phy-k3-usb3` + `fusb301` (Type-C) | — | USB2 host + USB3 portA(DRD)/portD + FUSB301 TCPC (irq `gpio 2/21`). |
| **WiFi** | `rtw89_8852be` (RTL8852BE, PCIe) | `rtw89/rtw8852b_fw.bin` | M.2 module; PCIe brought up (K3 PCIe PHY + RC). |
| **Bluetooth** | `btusb` + `btrtl` (RTL8852B, USB) | `rtl_bt/rtl8852bu_*` | standard Android BT HAL (USB HCI, no UART transport). |
| **Storage (UFS)** | `ufs-spacemit.ko` (`spacemit,k3-ufshcd`) | — | boot device; loaded from the vendor_boot ramdisk. |
| **Audio (DP)** | `snd-soc-k3-ri2s` + `adma-spacemit` (RCPU domain) → DP codec | — | DP-audio over the DisplayPort (Linux-direct, no RT-coprocessor firmware). |

**Known gaps (need the board, or further work):**

- **Analog audio (ES8326)** sits on a *secure* I²C bus (`i2c3@f0614000`, APBC2)
  not exposed to Linux in this tree → the analog headphone codec is not wired;
  DP-audio is the available path.
- All of the above is compile/integration-level; **runtime validation requires
  the hardware** (PCIe link-up, UFS enumeration, DP link-training, etc.).

## Storage (UFS, not eMMC)

`androidboot.boot_devices` points at the UFS host (`soc/c0e00000.ufshc`); the
fstab uses bus-agnostic `/dev/block/by-name/*` (resolved off the GPT PARTLABEL
on the UFS user LU). `ufs-spacemit.ko` is force-loaded early via
`BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD` so UFS probes before first-stage
mount. The bootloader (U-Boot 2026.07) already has UFS + the K3 controller.

## Bootloader staging

Built from **upstream U-Boot 2026.07 + OpenSBI** (K3 port) through the **same
build-bootloaders env as the K1** — `release_android.sh` driven by
`config/boards/spacemit-k3.yaml` — and staged to `vendor/spacemit/k3/bootloader/`
(`u-boot-release.itb`, `fw_dynamic`, `env`, `factory/{FSBL,bootinfo_*}`).
`release_android.sh` itself is unmodified; the K3 is a new yaml + minimal,
default-preserving generalization of the shared shell helpers (the K1 build is
byte-for-byte unchanged).

## Flashing

Use `flash_pico_itx.sh` (staged to `PRODUCT_OUT`). The board enters flashing
mode via the **FDL** button; flashing is over the **DRD Type-C** port with the
official `Titan` tool or `fastboot`. Bootloader → SPI-NOR, Android → UFS.

```sh
./flash_pico_itx.sh --android-media=ufs      # Android to UFS (default for this board)
./flash_pico_itx.sh --help                   # all modes
```

> The flash flow (GPT to UFS, U-Boot fastboot SCSI backend) is self-flagged
> UNVALIDATED in the script — it needs board validation.

## See also

- `flash_pico_itx.sh` — the flash tool.
- `device/spacemit/k1/README.md` — the K1 boards (BPI-F3, MusePi Pro) that share
  this kernel.
- `README.fr.md` — French version of this document.
