# Fix: microSD card not detected on Xiaomi Redmi 7A (pine) under mainline Linux

**Status: fixed and verified on real hardware.**

| | |
|---|---|
| Device | Xiaomi Redmi 7A — codename `pine` / Mi439 (Qualcomm SDM439) |
| Device tree | `arch/arm64/boot/dts/qcom/sdm439-xiaomi-pine.dts` |
| Kernel tested | **7.1.3-msm89x7** (postmarketOS / Nura edge) |
| Symptom | SD card inserted, but no `/dev/mmcblk1` ever appears |
| Root cause | **`vqmmc-supply` points at a 1.8 V-only regulator**, board needs 3.3 V I/O |
| Fix | `vqmmc-supply = <&pm8953_l11>` + `no-1-8-v;` + `broken-cd;` |

## Symptom in detail

`mmc@7864900` (SDC2) probes fine, the card-detect GPIO works, but the card is
never powered up and no block device is created:

```
$ grep mmcblk1 /proc/partitions        # (nothing)
$ sudo dmesg | grep mmc1
mmc1: SDHCI controller on 7864900.mmc [7864900.mmc] using ADMA 64-bit
$ cat /sys/kernel/debug/mmc1/ios
clock:      0 Hz
vdd:        0 (invalid)
power mode: 0 (off)
```

Forcing a rescan shows the controller does try, and the card does not answer:

```
mmc1: mmc_rescan_try_freq: trying to init card at 400000 Hz
mmc1: starting CMD0  -> 0        (reset, no response needed)
mmc1: starting CMD8  -> -110     (timeout - card did not reply)
mmc1: starting CMD5  -> -110     (timeout)
```

## Root cause

The upstream device tree has:

```dts
&sdhc_2 {
	cd-gpios = <&tlmm 67 GPIO_ACTIVE_HIGH>;
	vmmc-supply = <&pm8953_l11>;   /* 3.3 V  - slot power  */
	vqmmc-supply = <&pm8953_l12>;  /* 1.8 V  - I/O level   */
	...
};
```

`pm8953_l12` is limited to 1.8 V:

```
l12 { regulator-max-microvolt = <0x1b7740>; };   /* 1 800 000 uV */
```

but this board drives the microSD I/O at 3.3 V. With the I/O rail at 1.8 V the
card never receives valid commands, so every CMD times out and the card is
treated as absent.

Cross-check that it is board-specific, not SoC-specific: the same SoC on
`sdm439-nokia-panther` uses SDC2 successfully in the same tree.

## The fix

```dts
&sdhc_2 {
	cd-gpios = <&tlmm 67 GPIO_ACTIVE_HIGH>;
	vmmc-supply = <&pm8953_l11>;
	/*
	 * The SD slot I/O is 3.3 V on this board. pm8953_l12 is limited to
	 * 1.8 V, so the card never answers CMD8/CMD5 and is not detected.
	 */
	vqmmc-supply = <&pm8953_l11>;
	no-1-8-v;
	broken-cd;
	...
};
```

* `vqmmc-supply = <&pm8953_l11>` - reuse the 3.3 V rail for I/O
* `no-1-8-v` - never switch to 1.8 V signalling
* `broken-cd` - the card-detect IRQ never fires on this board, so poll instead

## Verification

```
mmc1: new high speed SDHC card at address 0001
mmcblk1: mmc1:0001 SD16G 29.8 GiB
 mmcblk1: p1
```

```
$ df -h /mnt/sdcard
/dev/mmcblk1p1   29.8G   320K   29.8G   0% /mnt/sdcard
```

Survives reboot, auto-mounts via `/etc/fstab`:

```
UUID=E69E-FFC6  /mnt/sdcard  exfat  defaults,nofail,noatime,uid=10000,gid=10000  0 0
```

## How to apply

### A. Kernel source (proper way)
```
git am patches/0001-arm64-dts-qcom-sdm439-pine-fix-sd-detection.patch
```

### B. Live device, no rebuild (what we used)
```
sudo apk add dtc python3
sudo sh scripts/apply-dtb-fix.sh
sudo reboot
```
Revert with `sudo sh scripts/apply-dtb-fix.sh --revert`.

## False leads (so you don't repeat them)

These were all tested and made **no** difference:

| Attempt | Result |
|---|---|
| `broken-cd` alone | DT property applied, still no card |
| `l11` (`vmmc`) marked `regulator-always-on` | rail enabled, still no card |
| `no-1-8-v` alone | still no card |
| `sdhci_msm` unbind/bind to force rescan | rescan runs, CMD8/CMD5 still time out |
| Checking CD GPIO | works correctly: high with card, low without |
| Checking DT pinctrl | `sdc2_clk/cmd/data` all present and correct |

**Lesson: when an SD card "does not respond" at the protocol level, check the
I/O rail (`vqmmc`) first, then the main rail (`vmmc`). Power on the main rail
does not mean the levels are right.**

## License

Same as the kernel: GPL-2.0-only.
