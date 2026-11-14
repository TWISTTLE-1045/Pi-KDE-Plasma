#!/usr/bin/env bash
# ==============================================================================
# Install KDE plasma-initial-setup (APT primary + KDE Git source build fallback)
# Target: Debian 13 (Trixie) arm64 inside chroot
# Includes fix for upstream KDE/kiss 50% display scaling & KScreen cursor reset bug
# ==============================================================================

set -euo pipefail

echo "======================================================================"
echo " Installing Native KDE First-Boot Wizard (plasma-initial-setup)"
echo "======================================================================"

export DEBIAN_FRONTEND=noninteractive

PATCH_STAMP="/usr/share/kde-initial-system-setup/.scaling-100-patched"

# Step 0: Fast path for --resume only if already built WITH the 100% scaling patch
if [ -x /usr/bin/plasma-initial-setup ] && [ -f "${PATCH_STAMP}" ]; then
    echo "✓ Patched plasma-initial-setup is already installed in chroot (skipping rebuild)."
else
    echo "==> Building patched plasma-initial-setup (KDE Initial System Setup) from source..."

    BUILD_DEPS=(
        git
        build-essential
        cmake
        extra-cmake-modules
        ninja-build
        pkg-config
        gettext
        qt6-base-dev
        qt6-base-private-dev
        qt6-declarative-dev
        qt6-declarative-private-dev
        qt6-wayland-dev
        qt6-svg-dev
        libkf6config-dev
        libkf6coreaddons-dev
        libkf6i18n-dev
        libkf6auth-dev
        libkf6package-dev
        libkirigami-dev
        kirigami-addons-dev
        libkscreen-dev
        plasma-workspace-dev
        libaccountsservice-dev
        network-manager-dev
        libcrypt-dev
    )

    EXTRA_DEPS=(
        libkf6kirigami-dev
        libkf6kirigami2-dev
        libnm-dev
        libkf6windowsystem-dev
        libkf6kcmutils-dev
        libkf6widgetsaddons-dev
        libkf6service-dev
        libpwquality-dev
        libpolkit-qt6-1-dev
        qt6-5compat-dev
    )

    echo "==> Installing mandatory KF6/Kirigami/Qt6 build dependencies..."
    apt-get install -y --no-install-recommends "${BUILD_DEPS[@]}"

    echo "==> Installing supplementary KF6 development headers (if available)..."
    for pkg in "${EXTRA_DEPS[@]}"; do
        apt-get install -y --no-install-recommends "${pkg}" 2>/dev/null || true
    done

    SRC_DIR="/tmp/plasma-initial-setup-src"
    rm -rf "${SRC_DIR}"

    echo "==> Cloning KDE plasma-initial-setup repository..."
    if ! git clone --depth 1 https://github.com/KDE/kiss.git "${SRC_DIR}" 2>/dev/null; then
        git clone --depth 1 https://invent.kde.org/system/plasma-initial-setup.git "${SRC_DIR}"
    fi

    # 1. Ensure CMakeLists.txt is compatible with Debian 13 Trixie's Qt 6.8.2
    if [ -f "${SRC_DIR}/CMakeLists.txt" ]; then
        sed -i 's/QT 6.8.3/QT 6.8.2/g' "${SRC_DIR}/CMakeLists.txt" 2>/dev/null || true
        sed -i 's/kde_clang_format/# kde_clang_format/g' "${SRC_DIR}/CMakeLists.txt" 2>/dev/null || true
        sed -i 's/kde_configure_git_pre_commit_hook/# kde_configure_git_pre_commit_hook/g' "${SRC_DIR}/CMakeLists.txt" 2>/dev/null || true
    fi

    # 2. Fix upstream bug where PrepareUtil initializes m_scaling uninitialized and defaults
    #    ComboBox index 0 to "50%" scaling (which shrank the taskbar/icons to 50% and caused
    #    KWin Wayland cursor resets to the top-left corner via KScreen::SetConfigOperation).
    if [ -f "${SRC_DIR}/modules/prepare/prepareutil.h" ]; then
        sed -i 's/int m_scaling;/int m_scaling = 100;/' "${SRC_DIR}/modules/prepare/prepareutil.h"
    fi
    if [ -f "${SRC_DIR}/modules/prepare/prepareutil.cpp" ]; then
        sed -i '/u"50%"_s,/d; /u"75%"_s,/d' "${SRC_DIR}/modules/prepare/prepareutil.cpp"
        sed -i 's/if (!m_config) {/if (!m_config || scaling == m_scaling || scaling < 100) {/' "${SRC_DIR}/modules/prepare/prepareutil.cpp"
    fi

    echo "==> Configuring plasma-initial-setup with CMake..."
    cmake -S "${SRC_DIR}" -B "${SRC_DIR}/build" \
        -G Ninja \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF

    echo "==> Compiling plasma-initial-setup..."
    cmake --build "${SRC_DIR}/build" --parallel "$(nproc)"

    echo "==> Installing plasma-initial-setup into /usr..."
    cmake --install "${SRC_DIR}/build"

    mkdir -p /usr/share/kde-initial-system-setup
    touch "${PATCH_STAMP}"
    rm -rf "${SRC_DIR}"
    echo "✓ Built and installed patched plasma-initial-setup from source."
fi

# Step 2: Normalize binary path so 'plasma-initial-setup' is always in /usr/bin
for candidate in \
    /usr/lib/aarch64-linux-gnu/libexec/kde-initial-system-setup \
    /usr/libexec/kde-initial-system-setup \
    /usr/libexec/plasma-initial-setup \
    /usr/lib/aarch64-linux-gnu/libexec/plasma-initial-setup \
    /usr/bin/kde-initial-system-setup; do
    if [ -x "${candidate}" ]; then
        ln -sf "${candidate}" /usr/bin/plasma-initial-setup
        echo "✓ Linked ${candidate} -> /usr/bin/plasma-initial-setup"
        break
    fi
done

if [ ! -x /usr/bin/plasma-initial-setup ]; then
    echo "❌ ERROR: plasma-initial-setup binary was not found after installation!"
    exit 1
fi

# Step 3: Ensure desktop file exists for session/application registration
mkdir -p /usr/share/applications
if [ ! -f /usr/share/applications/org.kde.plasma-initial-setup.desktop ] && \
   [ ! -f /usr/share/applications/plasma-initial-setup.desktop ]; then
    cat <<'EOF' > /usr/share/applications/org.kde.plasma-initial-setup.desktop
[Desktop Entry]
Type=Application
Name=Plasma Initial Setup
Comment=KDE Plasma First-Boot System Configuration Wizard
Exec=/usr/bin/plasma-initial-setup
Icon=preferences-system
Terminal=false
Categories=System;Settings;
NoDisplay=true
EOF
fi

echo "✓ plasma-initial-setup installation verified successfully."
