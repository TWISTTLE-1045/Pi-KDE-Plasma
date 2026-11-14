#!/usr/bin/env bash
# ==============================================================================
# Pre-Pack Image Verification Script (verify-image.sh)
# Can be run directly inside the arm64 chroot OR from the host by passing the
# rootfs mount path: ./verify-image.sh [ROOTFS_PATH]
# ==============================================================================

set -uo pipefail

ROOTFS="${1:-/}"
# Normalize trailing slash
if [ "${ROOTFS}" != "/" ]; then
    ROOTFS="${ROOTFS%/}"
else
    ROOTFS=""
fi

ERRORS=0

pass() {
    echo "  [PASS] $1"
}

fail() {
    echo "  [FAIL] $1"
    ERRORS=$((ERRORS + 1))
}

echo "======================================================================"
echo " 🔍 Running Pre-Pack Image Verification (Target: ${ROOTFS:-/})"
echo "======================================================================"

# ------------------------------------------------------------------------------
# 1. Verify plasma-initial-setup binary & desktop/OEM files exist
# ------------------------------------------------------------------------------
echo "==> 1. Checking Native KDE First-Boot Wizard (plasma-initial-setup)..."

if [ -x "${ROOTFS}/usr/bin/plasma-initial-setup" ] || \
   [ -x "${ROOTFS}/usr/libexec/plasma-initial-setup" ] || \
   [ -x "${ROOTFS}/usr/lib/aarch64-linux-gnu/libexec/plasma-initial-setup" ]; then
    pass "plasma-initial-setup binary exists and is executable"
else
    fail "plasma-initial-setup binary is missing!"
fi

if [ -f "${ROOTFS}/usr/share/applications/org.kde.plasma-initial-setup.desktop" ] || \
   [ -f "${ROOTFS}/usr/share/applications/plasma-initial-setup.desktop" ]; then
    pass "plasma-initial-setup .desktop entry exists"
else
    fail "plasma-initial-setup .desktop file is missing in /usr/share/applications!"
fi

if [ -x "${ROOTFS}/usr/libexec/plasma-initial-setup-session" ] && \
   [ -f "${ROOTFS}/home/oem/.config/autostart/org.kde.plasma-initial-setup.desktop" ]; then
    pass "OEM first-boot session runner and autostart desktop entry exist"
else
    fail "OEM first-boot session runner or autostart desktop entry is missing!"
fi

if [ ! -e "${ROOTFS}/etc/xdg/autostart/org.kde.plasma-welcome.desktop" ]; then
    pass "/etc/xdg/autostart/org.kde.plasma-welcome.desktop is removed (no collision)"
else
    fail "/etc/xdg/autostart/org.kde.plasma-welcome.desktop still exists!"
fi

# ------------------------------------------------------------------------------
# 2. Verify userconfig.service is disabled/masked & piwiz is NOT installed
# ------------------------------------------------------------------------------
echo "==> 2. Checking Raspberry Pi stock piwiz / userconfig.service removal..."

if [ -f "${ROOTFS}/usr/bin/piwiz" ]; then
    fail "piwiz binary (/usr/bin/piwiz) is installed (must NOT be present)!"
else
    pass "piwiz is not installed"
fi

if [ -e "${ROOTFS}/etc/systemd/system/multi-user.target.wants/userconfig.service" ] || \
   [ -e "${ROOTFS}/etc/systemd/system/graphical.target.wants/userconfig.service" ]; then
    fail "userconfig.service is still enabled in systemd target wants!"
else
    pass "userconfig.service is disabled"
fi

# ------------------------------------------------------------------------------
# 3. Verify SDDM Wayland configuration is valid
# ------------------------------------------------------------------------------
echo "==> 3. Checking SDDM Wayland & kwin_wayland configuration..."

SDDM_WAYLAND_CONF="${ROOTFS}/etc/sddm.conf.d/10-wayland.conf"
if [ -f "${SDDM_WAYLAND_CONF}" ]; then
    if grep -q "^DisplayServer=wayland" "${SDDM_WAYLAND_CONF}"; then
        pass "SDDM Wayland configuration (/etc/sddm.conf.d/10-wayland.conf) is valid"
    else
        fail "SDDM Wayland config is missing DisplayServer=wayland!"
    fi
else
    fail "/etc/sddm.conf.d/10-wayland.conf does not exist!"
fi

if [ -f "${ROOTFS}/etc/sddm.conf.d/99-oem-firstboot.conf" ] && \
   grep -q "^User=oem" "${ROOTFS}/etc/sddm.conf.d/99-oem-firstboot.conf"; then
    pass "SDDM OEM first-boot autologin config (/etc/sddm.conf.d/99-oem-firstboot.conf) is present"
else
    fail "/etc/sddm.conf.d/99-oem-firstboot.conf is missing or invalid!"
fi

# ------------------------------------------------------------------------------
# 4. Verify no hardcoded 'pi' user remains
# ------------------------------------------------------------------------------
echo "==> 4. Checking that no hardcoded 'pi' user remains..."

if grep -q "^pi:" "${ROOTFS}/etc/passwd" 2>/dev/null; then
    fail "Hardcoded 'pi' user still exists in /etc/passwd!"
else
    pass "No hardcoded 'pi' user in /etc/passwd"
fi

if [ -d "${ROOTFS}/home/pi" ]; then
    fail "/home/pi directory still exists!"
else
    pass "/home/pi directory does not exist"
fi

# ------------------------------------------------------------------------------
# 5. Verify clean stock state (no custom themes, Pi-Apps, or PiKISS)
# ------------------------------------------------------------------------------
echo "==> 5. Checking clean stock KDE state (no custom themes or third-party stores)..."

if [ ! -d "${ROOTFS}/opt/pi-apps" ] && \
   [ ! -d "${ROOTFS}/opt/piKiss" ] && \
   [ ! -d "${ROOTFS}/usr/share/sddm/themes/pibreeze" ]; then
    pass "Image is clean (no Pi-Apps, PiKISS, or custom theme overrides)"
else
    fail "Leftover custom themes or third-party stores found in image!"
fi

echo "======================================================================"
if [ "${ERRORS}" -eq 0 ]; then
    echo " ✅ ALL PRE-PACK VERIFICATION CHECKS PASSED! Ready to pack .img."
    echo "======================================================================"
    exit 0
else
    echo " ❌ PRE-PACK VERIFICATION FAILED WITH ${ERRORS} ERROR(S)!"
    echo "======================================================================"
    exit 1
fi
