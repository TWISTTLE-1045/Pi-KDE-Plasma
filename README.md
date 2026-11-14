# Pi KDE Plasma — Raspberry Pi OS (Debian 13 Trixie, `arm64`)

<p align="center">
  <img src="https://img.shields.io/badge/OS-Raspberry%20Pi%20OS%20Lite-C51A4A?style=for-the-badge&logo=raspberrypi&logoColor=white" alt="Raspberry Pi OS">
  <img src="https://img.shields.io/badge/Desktop-KDE%20Plasma%206%20(Wayland)-1D99F3?style=for-the-badge&logo=kde&logoColor=white" alt="KDE Plasma 6">
  <img src="https://img.shields.io/badge/Base-Debian%2013%20(Trixie)-A80030?style=for-the-badge&logo=debian&logoColor=white" alt="Debian 13 Trixie">
  <img src="https://img.shields.io/badge/Arch-ARM64%20(aarch64)-0091BD?style=for-the-badge&logo=arm&logoColor=white" alt="ARM64">
  <br/>
  <a href="https://sourceforge.net/projects/pi-kde-plasma/files/v1.0.0/">
    <img src="https://img.shields.io/badge/Download%20Image-SourceForge-FF6600?style=for-the-badge&logo=sourceforge&logoColor=white" alt="Download on SourceForge">
  </a>
</p>

<p align="center">
  <b>Automated ARM64 Chroot Image Builder for Raspberry Pi 5 &amp; Raspberry Pi 4</b><br/>
  Pure, unmodified upstream KDE Plasma (Wayland) built directly on top of official <b>Raspberry Pi OS Lite (64-bit)</b> with complete Raspberry Pi hardware drivers and a native <b>KDE First-Boot Setup Wizard (<code>plasma-initial-setup</code>)</b>.
</p>

---

## Overview

Most third-party desktop builds for Raspberry Pi either rely on heavy custom themes, third-party repositories, or broken scripts that interfere with upstream package updates and DPI scaling.

This project takes a **100% clean, upstream-first approach**:
1. Starts from the **official Raspberry Pi OS Lite (64-bit / `arm64`)** image so the official Raspberry Pi kernel, bootloader, and APT repositories remain completely intact.
2. Installs **standard, unmodified KDE Plasma (`kde-plasma-desktop`, `sddm`, `plasma-nm`, `fonts-noto-core`)** with native **Wayland (`kwin_wayland`)** enabled out of the box.
3. Replaces Raspberry Pi's GTK-based `piwiz` first-boot tool with **KDE's native Out-of-the-Box Setup Wizard (`plasma-initial-setup` / `KDE/kiss`)**, allowing the end user to configure language, keyboard layout, Wi-Fi, timezone, and their primary user account (`UID 1000`) on first boot.
4. Includes all essential **Raspberry Pi hardware drivers** (VideoCore VII Vulkan/OpenGL Mesa drivers, PipeWire audio, Bluetooth, Wi-Fi firmware, EEPROM tools, and GPIO/I2C/SPI libraries).

---

## Key Features

- **Pure Stock KDE Plasma (Wayland)**:
  - Unmodified KDE Breeze look-and-feel, native display scaling, standard panel layout, and SDDM Wayland login manager.
  - Zero bloatware (`akonadi`, `kmail`, `libreoffice`, and third-party script stores are excluded).
- **Native KDE First-Boot OEM Wizard (`plasma-initial-setup`)**:
  - Boots directly into a fullscreen Kirigami/Qt6 setup wizard on first power-on.
  - Automatically assigns the newly created user (`UID 1000`) to all standard Raspberry Pi hardware and administrative groups (`sudo`, `gpio`, `i2c`, `spi`, `video`, `render`, `audio`, `bluetooth`, `netdev`, `plugdev`, `dialout`).
  - Automatically purges the temporary OEM setup account and transitions cleanly to the standard SDDM login screen upon completion.
  - Includes upstream fixes for native `100%` display scaling and Wayland HDMI CEC input handling.
- **Complete Raspberry Pi Hardware Support**:
  - **Graphics**: `mesa-vulkan-drivers`, `mesa-va-drivers`, `libgl1-mesa-dri` (`vc4-kms-v3d`).
  - **Firmware & System**: `raspi-firmware`, `raspberrypi-sys-mods`, `raspi-config`, `raspi-utils`, `rpi-eeprom`.
  - **Connectivity & Audio**: `NetworkManager` (`plasma-nm`), `pi-bluetooth`, `bluez-firmware`, `firmware-brcm80211`, `pipewire-audio`, `libspa-0.2-bluetooth`.
  - **GPIO / Peripherals**: `gpiod`, `i2c-tools`, `python3-gpiozero`, `python3-rpi-lgpio`, `python3-smbus2`, `python3-spidev`.

---

## Repository Structure

```text
.
├── build-image.sh                              # Core ARM64 QEMU chroot image builder (Linux & WSL2)
├── build-wsl.sh / build_wsl.sh                 # 1-command WSL2 wrapper (syncs to ext4 & exports .img)
├── verify-image.sh                             # Pre-pack automated verification suite
├── scripts/
│   ├── chroot-setup.sh                         # Chroot provisioning (KDE Plasma, drivers & SDDM Wayland)
│   ├── install-plasma-initial-setup.sh         # Builds & installs patched KDE plasma-initial-setup
│   └── oem-firstboot-runner.sh                 # First-boot OEM session lifecycle & cleanup runner
└── configs/
    ├── polkit/
    │   └── 90-plasma-initial-setup.rules       # Temporary Polkit permissions for first-boot setup
    ├── sddm/
    │   ├── 10-wayland.conf                     # SDDM Wayland compositor config (kwin_wayland)
    │   └── 99-oem-firstboot.conf               # Temporary first-boot autologin config (removed after setup)
    └── systemd/
        └── plasma-initial-setup-cleanup.service # Ensures temporary OEM user is purged after setup
```

---

## Building the Image

### Option A: Building on Windows via WSL2 (Ubuntu / Debian)

Because mounting Linux loop partitions and chrooting into `ext4` with POSIX permissions requires a native Linux filesystem, `build_wsl.sh` automatically syncs the project into your WSL home directory (`~/Pi-KDE-Plasma`), runs the build, and copies the finished `.img` / `.img.xz` back to your Windows `output/` folder.

1. Open your **WSL2 Ubuntu** terminal and run:
   ```bash
   "/mnt/c/path/to/Pi-KDE-Plasma/build_wsl.sh" --compress
   ```
2. If a build is interrupted (e.g., network timeout), you can resume from the existing working image without starting over:
   ```bash
   "/mnt/c/path/to/Pi-KDE-Plasma/build_wsl.sh" --resume --compress
   ```

### Option B: Building on Native Linux (Ubuntu / Debian Host)

```bash
git clone https://github.com/TWISTTLE-1045/Pi-KDE-Plasma.git
cd Pi-KDE-Plasma
sudo ./build-image.sh --compress
```

### Build CLI Options (`build-image.sh` / `build_wsl.sh`)

| Flag | Description |
| :--- | :--- |
| `--compress`, `-z` | Compresses the final `.img` into a flash-ready `.img.xz` archive with `.sha256` checksums |
| `--resume`, `-r` | Resumes provisioning on an existing `work/working-raspios-trixie-arm64.img` |
| `--base-image <path>` | Uses a specific local Raspberry Pi OS Lite `.img` or `.img.xz` file instead of downloading |
| `--expand-gb <size>` | Additional space (in GB) added to the root partition during build (default: `6`) |

---

## Flashing & First-Boot Guide

1. **Flash the Image**:
   - Open **[Raspberry Pi Imager](https://www.raspberrypi.com/software/)**, **[BalenaEtcher](https://etcher.balena.io/)**, or **[Rufus](https://rufus.ie/)**.
   - Select the generated `RaspberryPiOS-13-Trixie-KDE-Plasma-arm64-YYYY-MM-DD.img.xz` file from `output/`.
   - *(Important)* If using Raspberry Pi Imager, choose **"No"** when asked to apply OS customisation settings — user creation, Wi-Fi, and locale are handled natively on first boot by KDE.
2. **First Boot (`plasma-initial-setup`)**:
   - Insert the microSD card or NVMe drive into your Raspberry Pi and power it on.
   - Complete the fullscreen **KDE Initial System Setup** wizard (Language, Keyboard Layout, Display Scaling, Wi-Fi, Timezone, and User Account creation).
3. **Standard Login**:
   - Once you click **Finish**, the temporary OEM setup environment is automatically removed and the system transitions to the **SDDM Wayland Login Screen** with your newly created account.

---

## Pre-Pack Verification

Before finalizing and unmounting the `.img`, `build-image.sh` automatically runs [`verify-image.sh`](verify-image.sh) inside the chroot to verify:
- `plasma-initial-setup` binary, `.desktop` launcher, and OEM session runner are installed.
- `org.kde.plasma-welcome.desktop` is diverted/removed so it does not collide with initial setup.
- Stock `piwiz` is absent and `userconfig.service` is disabled/masked.
- `/etc/sddm.conf.d/10-wayland.conf` and `/etc/sddm.conf.d/99-oem-firstboot.conf` are valid.
- No hardcoded `pi` user exists in `/etc/passwd` or `/home/pi`.

---

## License

Released under the [BSD 3-Clause License](https://opensource.org/licenses/BSD-3-Clause).
