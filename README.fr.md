# SpacemiT K3 (RISC-V) — support device Android

Ce répertoire est la config device AOSP du SoC **SpacemiT K3**
(`spacemit,x100` ; 8 cœurs RVA23 out-of-order, RVV/RVH, NPU A100, GPU PowerVR
BXM-4-64, riscv64). Il cible la board **Muse Pico-ITX**.

Le K3 partage **un kernel commun avec le K1** (cf. « Kernel » plus bas) : un
seul `Image` type GKI + des DTB par board + un set de modules unifié. Les
drivers SoC bindent par `compatible` device-tree, donc K1 et K3 coexistent dans
le même tree sans régression pour l'un ni l'autre.

| Board | SoC | `compatible` | Média bootloader | Média Android |
|---|---|---|---|---|
| **Muse Pico-ITX** | K3 / x100 | `spacemit,k3-pico-itx`, `spacemit,k3` | **SPI-NOR** | **UFS 2.2** |

> La board boote son bootloader depuis la **SPI-NOR**, puis Android depuis
> l'**UFS** (UFS 2.2, 128/256 Go — pas d'eMMC). La LU user UFS porte la GPT ;
> le bootloader vit sur la NOR. Cf. « Storage » plus bas.

## Un device, un produit

Le device est `k3` ; le produit lunch est dans `k3_pico_itx/` :

- `aosp_k3_pico_itx` — `lunch aosp_k3_pico_itx-trunk_staging-userdebug`

`device/spacemit/k3/device.mk` hérite de `device/spacemit/common` (HALs
SoC-agnostiques, stack GPU Mesa, A/B, codecs, webview, …) et ajoute le fstab,
l'init, le firmware et le câblage storage/WiFi/BT spécifiques au K3.

## Kernel : un seul build commun K1 + K3

Les deux SoC buildent depuis la **même cible kleaf** `spacemit_k1x` dans
`devices/spacemit/spacemit_soc/` (ce répertoire s'appelait historiquement
`bananapi_f3/` ; renommé car il n'est plus spécifique au K1/BPI-F3 — c'est le
kernel commun des SoC SpacemiT). DTB émises depuis
`common/arch/riscv/boot/dts/spacemit/` :

- `k1-bananapi-f3.dtb`, `k1-musepi-pro.dtb` (boards K1)
- `k3-pico-itx.dtb` (cette board)

Build / re-staging du prebuilt kernel :

```sh
cd <kernel>
./tools/bazel run --config=spacemit_k1x \
    //devices/spacemit/spacemit_soc:spacemit_k1x_dist -- \
    --destdir=<aosp>/device/spacemit/kernel/<version>
```

`<version>` est le répertoire que désigne `TARGET_KERNEL_USE` — `mainline`
(défaut) ou `6.18`, ce dernier construit depuis l'arbre `kernel-6.18/`. K1 et
K3 partagent un seul kernel : une drop zone par version, aucune par SoC.

Le fragment de config est `devices/spacemit/spacemit_soc/spacemit_k1x.fragment`
(les options K3 y sont gated/ajoutées ; les options K1 sont intactes).

## État du bring-up fonctionnel

Tous les périphériques ci-dessous sont **portés, build-GREEN, et foldés dans le
set d'images flashable**. La validation hardware (probe, scan-out,
link-training, énumération) reste à faire sur la board réelle.

| Fonction | Kernel | Firmware | Notes |
|---|---|---|---|
| **Display** | `spacemit-drm-k3.ko` (DPU saturn) + `spacemit_inno_dp.ko` (DP/eDP) | — | eDP 40-pin (2.5K) + USB-C DP (4K, DP-Alt-Mode). K3-gated, séparé du `spacemit-drm.ko` K1. |
| **GPU** | `drm/imagination` upstream **open-source** (`DRM_POWERVR`) ; BVNC **36.56.104.183** (BXM-4-64) | `powervr/rogue_36.56.104.183_v1.fw` | userspace = Mesa (≥26.1) `powervr_dri.so`. Firmware depuis le repo Imagination linux-firmware. |
| **USB** | `dwc3` + `phy-k3-usb2`/`phy-k3-usb3` + `fusb301` (Type-C) | — | USB2 host + USB3 portA(DRD)/portD + TCPC FUSB301 (irq `gpio 2/21`). |
| **WiFi** | `rtw89_8852be` (RTL8852BE, PCIe) | `rtw89/rtw8852b_fw.bin` | module M.2 ; PCIe bring-up (PHY PCIe K3 + RC). |
| **Bluetooth** | `btusb` + `btrtl` (RTL8852B, USB) | `rtl_bt/rtl8852bu_*` | HAL BT Android standard (HCI USB, pas de transport UART). |
| **Storage (UFS)** | `ufs-spacemit.ko` (`spacemit,k3-ufshcd`) | — | device de boot ; chargé depuis le ramdisk vendor_boot. |
| **Audio (DP)** | `snd-soc-k3-ri2s` + `adma-spacemit` (domaine RCPU) → codec DP | — | audio DP sur le DisplayPort (Linux-direct, sans firmware coprocesseur RT). |

**Limitations connues (board ou travail supplémentaire requis) :**

- Le **codec analog (ES8326)** est sur un bus I²C *secure* (`i2c3@f0614000`,
  APBC2) non exposé à Linux dans ce tree → le codec jack analog n'est pas
  câblé ; le path disponible est l'audio DP.
- Tout ce qui précède est au niveau compile/intégration ; la **validation
  runtime exige le hardware** (link-up PCIe, énumération UFS, link-training DP…).

## Storage (UFS, pas eMMC)

`androidboot.boot_devices` pointe sur le host UFS (`soc/c0e00000.ufshc`) ; le
fstab utilise des `/dev/block/by-name/*` agnostiques du bus (résolus via le
PARTLABEL GPT sur la LU user UFS). `ufs-spacemit.ko` est forcé tôt via
`BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD` pour que l'UFS probe avant le mount
first-stage. Le bootloader (U-Boot 2026.07) a déjà l'UFS + le controller K3.

## Staging du bootloader

Buildé depuis **U-Boot 2026.07 + OpenSBI upstream** (port K3) via le **même env
build-bootloaders que le K1** — `release_android.sh` piloté par
`config/boards/spacemit-k3.yaml` — et stagé dans `vendor/spacemit/k3/bootloader/`
(`u-boot-release.itb`, `fw_dynamic`, `env`, `factory/{FSBL,bootinfo_*}`).
`release_android.sh` lui-même n'est pas modifié ; le K3 = un nouveau yaml + une
généralisation minimale des helpers shell partagés préservant les défauts (le
build K1 est byte-for-byte inchangé).

## Flash

Utiliser `flash_pico_itx.sh` (stagé dans `PRODUCT_OUT`). La board entre en mode
flash via le bouton **FDL** ; le flash se fait sur le port **DRD Type-C** avec
l'outil officiel `Titan` ou `fastboot`. Bootloader → SPI-NOR, Android → UFS.

```sh
./flash_pico_itx.sh --android-media=ufs      # Android sur UFS (défaut pour cette board)
./flash_pico_itx.sh --help                   # tous les modes
```

> Le flow de flash (GPT vers UFS, backend fastboot SCSI U-Boot) est auto-flaggé
> UNVALIDATED dans le script — à valider sur la board.

## Voir aussi

- `flash_pico_itx.sh` — l'outil de flash.
- `device/spacemit/k1/README.fr.md` — les boards K1 (BPI-F3, MusePi Pro) qui
  partagent ce kernel.
- `README.md` — version anglaise de ce document.
