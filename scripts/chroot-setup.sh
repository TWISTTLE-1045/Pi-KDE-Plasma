#!/usr/bin/env bash
# ==============================================================================
# Clean Chroot Provisioning Script for Raspberry Pi 5
# Base: Raspberry Pi OS Lite (Debian 13 Trixie, arm64)
# Desktop: Clean KDE Plasma (Wayland) + Native KDE plasma-initial-setup OEM
# ==============================================================================

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

BUILD_ASSETS_DIR="/tmp/rpi-kde-build"

echo "======================================================================"
echo " [1/4] Disabling Stock RPi First-Boot (piwiz / userconfig.service)"
echo "======================================================================"

apt-mark hold piwiz userconf-pi 2>/dev/null || true
apt-get purge -y piwiz userconf-pi 2>/dev/null || true

systemctl disable userconfig.service 2>/dev/null || true
systemctl mask userconfig.service 2>/dev/null || true
rm -f /etc/systemd/system/multi-user.target.wants/userconfig.service 2>/dev/null || true
rm -f /etc/systemd/system/graphical.target.wants/userconfig.service 2>/dev/null || true

if id -u pi >/dev/null 2>&1; then
    userdel -rf pi 2>/dev/null || true
fi
rm -rf /home/pi 2>/dev/null || true

# Clean up any leftover custom files if resuming from an earlier build
rm -rf /opt/pi-apps /opt/piKiss /etc/skel/pi-apps /etc/skel/piKiss \
       /usr/local/bin/pi-apps /usr/local/bin/pikiss \
       /usr/share/applications/pi-apps.desktop /usr/share/applications/pikiss.desktop \
       /usr/share/pixmaps/piapps.png /usr/share/pixmaps/pikiss.png \
       /usr/share/rpd-wallpaper \
       /usr/share/plasma/look-and-feel/org.raspberrypi.pibreeze.desktop \
       /usr/share/plasma/desktoptheme/pibreeze \
       /usr/share/color-schemes/PiBreeze.colors \
       /usr/share/sddm/themes/pibreeze \
       /usr/share/sddm/themes/breeze/theme.conf.user \
       /etc/xdg/fastfetch /etc/fastfetch /etc/skel/.config/fastfetch \
       /etc/xdg/kcm-about-distrorc /etc/skel/.config/kcm-about-distrorc \
       /etc/xdg/kdeglobals /etc/skel/.config/kdeglobals \
       /etc/xdg/plasmarc /etc/skel/.config/plasmarc \
       /etc/xdg/kwinrc /etc/skel/.config/kwinrc \
       /etc/xdg/baloofilerc /etc/skel/.config/baloofilerc \
       /etc/xdg/baloorc /etc/skel/.config/baloorc \
       /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc \
       /etc/systemd/zram-generator.conf /etc/sysctl.d/99-rpi5-performance.conf 2>/dev/null || true

# Remove any custom usbhid.mousepoll parameter from cmdline.txt if resuming
for cmdline in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
    if [ -f "${cmdline}" ]; then
        sed -i 's/ usbhid\.mousepoll=[0-9]*//g' "${cmdline}"
    fi
done

echo "======================================================================"
echo " [2/4] Installing Clean KDE Plasma Desktop & Raspberry Pi OS Drivers"
echo "======================================================================"

apt-get update -y
apt-get install -y \
    kde-plasma-desktop \
    sddm \
    plasma-nm \
    fonts-noto-core \
    desktop-base \
    plasma-workspace-wallpapers \
    sddm-theme-breeze \
    sddm-theme-debian-breeze \
    raspi-firmware \
    raspberrypi-sys-mods \
    raspi-config \
    raspi-utils \
    rpi-eeprom \
    pi-bluetooth \
    bluez \
    bluez-firmware \
    firmware-brcm80211 \
    firmware-realtek \
    firmware-atheros \
    firmware-libertas \
    firmware-misc-nonfree \
    pipewire-audio \
    libspa-0.2-bluetooth \
    mesa-vulkan-drivers \
    mesa-va-drivers \
    libgl1-mesa-dri \
    i2c-tools \
    gpiod \
    python3-gpiozero \
    python3-rpi-lgpio \
    python3-smbus2 \
    python3-spidev

echo "======================================================================"
echo " [3/4] Installing Native KDE First-Boot Wizard (plasma-initial-setup)"
echo "======================================================================"

chmod +x "${BUILD_ASSETS_DIR}/scripts/install-plasma-initial-setup.sh"
"${BUILD_ASSETS_DIR}/scripts/install-plasma-initial-setup.sh"

# Remove org.kde.plasma-welcome.desktop so it does not collide with plasma-initial-setup
dpkg-divert --add --rename --divert /etc/xdg/autostart/org.kde.plasma-welcome.desktop.disabled \
    /etc/xdg/autostart/org.kde.plasma-welcome.desktop 2>/dev/null || true
rm -f /etc/xdg/autostart/org.kde.plasma-welcome.desktop
rm -f /etc/xdg/autostart/org.kde.plasma-welcome.desktop.disabled
rm -f /usr/share/applications/org.kde.plasma-welcome.desktop 2>/dev/null || true

echo "======================================================================"
echo " [4/4] Configuring SDDM Wayland, OEM First-Boot & Graphical Target"
echo "======================================================================"

mkdir -p /etc/sddm.conf.d
install -v -m 644 "${BUILD_ASSETS_DIR}/configs/sddm/10-wayland.conf" /etc/sddm.conf.d/10-wayland.conf
install -v -m 644 "${BUILD_ASSETS_DIR}/configs/sddm/99-oem-firstboot.conf" /etc/sddm.conf.d/99-oem-firstboot.conf

# Prevent vc4-hdmi CEC devices from registering as fake pointer/mouse inputs in Wayland
mkdir -p /etc/udev/rules.d
cat <<'EOF' > /etc/udev/rules.d/99-rpi5-ignore-cec-mouse.rules
SUBSYSTEM=="input", ATTRS{name}=="vc4-hdmi*", ENV{ID_INPUT}="", ENV{ID_INPUT_MOUSE}="", ENV{ID_INPUT_POINTINGSTICK}="", ENV{LIBINPUT_IGNORE_DEVICE}="1"
EOF
chmod 644 /etc/udev/rules.d/99-rpi5-ignore-cec-mouse.rules

# Ensure plasmawayland.desktop alias exists if OEM config references it
if [ -f /usr/share/wayland-sessions/plasma.desktop ] && [ ! -f /usr/share/wayland-sessions/plasmawayland.desktop ]; then
    ln -sf /usr/share/wayland-sessions/plasma.desktop /usr/share/wayland-sessions/plasmawayland.desktop
elif [ -f /usr/share/wayland-sessions/plasmawayland.desktop ] && [ ! -f /usr/share/wayland-sessions/plasma.desktop ]; then
    ln -sf /usr/share/wayland-sessions/plasmawayland.desktop /usr/share/wayland-sessions/plasma.desktop
fi

# Create temporary 'oem' system user (UID < 1000) so it never shows on the SDDM user list
if id -u oem >/dev/null 2>&1; then
    if [ "$(id -u oem)" -ge 1000 ]; then
        userdel -rf oem 2>/dev/null || true
    fi
fi
if ! id -u oem >/dev/null 2>&1; then
    useradd -r -m -d /home/oem -s /bin/bash -c "KDE OEM Initial Setup" oem
fi
passwd -d oem >/dev/null 2>&1 || true

mkdir -p /var/lib/AccountsService/users
cat <<'EOF' > /var/lib/AccountsService/users/oem
[User]
SystemAccount=true
EOF
chmod 644 /var/lib/AccountsService/users/oem

for grp in sudo adm netdev video render input audio bluetooth plugdev; do
    if getent group "${grp}" >/dev/null 2>&1; then
        usermod -aG "${grp}" oem 2>/dev/null || true
    fi
done

mkdir -p /etc/sudoers.d
cat <<'EOF' > /etc/sudoers.d/90-oem-initial-setup
oem ALL=(ALL) NOPASSWD: ALL
EOF
chmod 440 /etc/sudoers.d/90-oem-initial-setup

mkdir -p /etc/polkit-1/rules.d
install -v -m 644 "${BUILD_ASSETS_DIR}/configs/polkit/90-plasma-initial-setup.rules" \
    /etc/polkit-1/rules.d/90-plasma-initial-setup.rules

mkdir -p /usr/libexec
install -v -m 755 "${BUILD_ASSETS_DIR}/scripts/oem-firstboot-runner.sh" \
    /usr/libexec/plasma-initial-setup-session

rm -f /etc/xdg/autostart/org.kde.plasma-initial-setup.desktop 2>/dev/null || true

mkdir -p /home/oem/.config/autostart
cat <<'EOF' > /home/oem/.config/autostart/org.kde.plasma-initial-setup.desktop
[Desktop Entry]
Type=Application
Name=Plasma Initial Setup
Comment=KDE Plasma First-Boot System Configuration Wizard
Exec=/usr/libexec/plasma-initial-setup-session
Icon=preferences-system
Terminal=false
X-KDE-AutostartPhase=1
X-KDE-StartupNotify=false
EOF
chown -R oem:oem /home/oem

install -v -m 644 "${BUILD_ASSETS_DIR}/configs/systemd/plasma-initial-setup-cleanup.service" \
    /etc/systemd/system/plasma-initial-setup-cleanup.service
systemctl enable plasma-initial-setup-cleanup.service 2>/dev/null || true

systemctl enable NetworkManager.service 2>/dev/null || true
systemctl enable sddm.service 2>/dev/null || true
systemctl set-default graphical.target

apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/plasma-initial-setup-src

echo "✓ Clean KDE Plasma chroot setup completed successfully!"
