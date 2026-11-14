#!/usr/bin/env bash
# ==============================================================================
# KDE Plasma First-Boot OEM Session Runner (/usr/libexec/plasma-initial-setup-session)
# Launches plasma-initial-setup on first boot, configures hardware groups for
# the newly created user, disables OEM mode, deletes the temporary 'oem' user,
# and transitions cleanly into standard SDDM Wayland.
# ==============================================================================

set -uo pipefail

LOG_FILE="/tmp/plasma-initial-setup.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "==> Starting KDE Plasma OEM Initial Setup Session..."

# Ensure Wayland environment variables are set for Qt6/Kirigami
export QT_QPA_PLATFORM="wayland;xcb"

# Disable screen blanking / locking during initial setup
kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false 2>/dev/null || true

# Helper function: Find newly created human user (UID >= 1000, not 'oem' or 'nobody')
find_created_user() {
    awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "oem" && $1 != "kde-initial-system-setup" && $1 != "initial-setup" && $1 != "nobody" { print $1; exit }' /etc/passwd
}

CLEANUP_DONE=0
finalize_oem_setup() {
    if [ "${CLEANUP_DONE}" -eq 1 ]; then
        return
    fi
    NEW_USER="$(find_created_user)"
    if [ -z "${NEW_USER}" ]; then
        return
    fi
    CLEANUP_DONE=1

    echo "==> Finalizing OEM setup for newly created user: ${NEW_USER}"
    RPI_GROUPS="sudo,adm,dialout,cdrom,audio,video,plugdev,games,users,input,render,netdev,gpio,i2c,spi,bluetooth,lpadmin"

    for usr in $(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "oem" && $1 != "kde-initial-system-setup" && $1 != "initial-setup" && $1 != "nobody" { print $1 }' /etc/passwd); do
        echo "==> Configuring Raspberry Pi hardware groups for user: ${usr}"
        for grp in $(echo "${RPI_GROUPS}" | tr ',' ' '); do
            if getent group "${grp}" >/dev/null 2>&1; then
                sudo usermod -aG "${grp}" "${usr}" 2>/dev/null || true
            fi
        done

        USER_HOME="$(getent passwd "${usr}" | cut -d: -f6)"
        if [ -n "${USER_HOME}" ] && [ -d "${USER_HOME}" ]; then
            sudo rm -f "${USER_HOME}/.config/autostart/org.kde.plasma-initial-setup.desktop" 2>/dev/null || true
            # Ensure no sub-100% display scaling (< 1.0) is carried over into the new user's session
            if [ -f "${USER_HOME}/.config/kwinoutputconfig.json" ] && grep -Eq '"scale":[[:space:]]*0\.' "${USER_HOME}/.config/kwinoutputconfig.json"; then
                sudo rm -f "${USER_HOME}/.config/kwinoutputconfig.json"
            fi
            sudo chown -R "${usr}:${usr}" "${USER_HOME}" 2>/dev/null || true
        fi
    done

    echo "==> Disabling OEM First-Boot autologin & scheduling immediate 'oem' removal..."
    sudo rm -f /etc/sddm.conf.d/99-oem-firstboot.conf /etc/sddm.conf.d/99-kde-initial-system-setup.conf
    sudo rm -f /etc/xdg/autostart/org.kde.plasma-initial-setup.desktop
    sudo rm -f /etc/xdg/autostart/org.kde.plasma-welcome.desktop
    sudo systemctl disable plasma-initial-setup.service kde-initial-system-setup.service 2>/dev/null || true

    sudo mkdir -p /var/lib
    sudo touch /var/lib/plasma-initial-setup-done
    sudo systemctl enable plasma-initial-setup-cleanup.service 2>/dev/null || true

    # Spawn detached root task to delete 'oem' account immediately after session exits
    sudo systemd-run --unit=oem-account-purge /bin/sh -c '
        sleep 2
        rm -f /etc/sddm.conf.d/99-oem-firstboot.conf /etc/sddm.conf.d/99-kde-initial-system-setup.conf
        rm -f /etc/polkit-1/rules.d/90-plasma-initial-setup.rules
        rm -f /etc/sudoers.d/90-oem-initial-setup
        rm -f /var/lib/AccountsService/users/oem
        pkill -9 -u oem 2>/dev/null || true
        userdel -rf oem 2>/dev/null || true
        rm -rf /home/oem
    ' >/dev/null 2>&1 || true

    sync
}

# Trap EXIT/HUP/TERM in case KDE Initial System Setup logs out the session directly via D-Bus
trap finalize_oem_setup EXIT HUP INT TERM

# Loop until the user completes plasma-initial-setup and creates their user account
while true; do
    echo "==> Launching /usr/bin/plasma-initial-setup..."
    /usr/bin/plasma-initial-setup || true

    NEW_USER="$(find_created_user)"
    if [ -n "${NEW_USER}" ]; then
        echo "✓ Detected newly created user account: ${NEW_USER}"
        finalize_oem_setup
        break
    fi

    echo "⚠️  No new user account detected yet. Re-launching plasma-initial-setup in 2 seconds..."
    sleep 2
done

echo "==> OEM Initial Setup complete! Rebooting into standard SDDM Wayland login screen..."
sudo systemctl reboot
