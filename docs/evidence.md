# Evidence chain (raw output from the device)

Device: Xiaomi Redmi 7A (pine), postmarketOS / Nura edge, kernel 7.1.3-msm89x7, aarch64.

## 1. Card-detect GPIO works

```
card inserted      ->  gpio67 : in high func0 2mA no pull
card removed       ->  gpio67 : in low  func0 2mA no pull
```

`/proc/interrupts` shows the CD line is registered but never fires:

```
47:   0  0 ... msmgpio  67 Edge  7864900.mmc cd
39:  19  0 ... GIC-0  157 Level  mmc1
```

## 2. Controller probes, never powers the card

```
$ cat /sys/kernel/debug/mmc1/ios
clock:       0 Hz
vdd:         0 (invalid)
power mode:  0 (off)
bus width:   0 (1 bits)

$ grep 7864900.mmc /sys/kernel/debug/regulator/regulator_summary
7864900.mmc-vmmc    0   0mA  3300mV  3300mV
7864900.mmc-vqmmc   0   0mV     0mV     0mV
```

## 3. Forced rescan: controller powers up, card does not answer

With `module mmc_core +p` dynamic debug enabled and a driver rebind:

```
mmc1: clock 400000Hz busmode 2 powermode 2 cs 0 Vdd 21 width 1 timing 0
mmc1: mmc_rescan_try_freq: trying to init card at 400000 Hz
mmc1: starting CMD0  -> req done (CMD0): 0: 00000000 ...
mmc1: starting CMD8  -> req done (CMD8): -110: 00000000 ...
mmc1: starting CMD5  -> req failed (CMD5): -110, retrying...
```

`-110` is `ETIMEDOUT`: the card did not respond.

## 4. Regulator limits (the actual bug)

```
l11: regulator-min-microvolt = <0x2d0370>  (2 950 000 uV)
     regulator-max-microvolt = <0x325aa0>  (3 300 000 uV)   <- vmmc target
l12: regulator-min-microvolt = <0x1b7740>  (1 800 000 uV)
     regulator-max-microvolt = <0x1b7740>  (1 800 000 uV)   <- vqmmc target
```

## 5. After the fix

```
mmc1: new high speed SDHC card at address 0001
mmcblk1: mmc1:0001 SD16G 29.8 GiB
 mmcblk1: p1

$ blkid /dev/mmcblk1p1
/dev/mmcblk1p1: UUID="E69E-FFC6" BLOCK_SIZE="512" TYPE="exfat"

$ df -h /mnt/sdcard
/dev/mmcblk1p1   29.8G   320K   29.8G   0% /mnt/sdcard
```

Verified again after a full reboot: card auto-mounted, services all up.
