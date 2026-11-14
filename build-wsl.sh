#!/usr/bin/env bash
# ==============================================================================
# 1-Command WSL2 Build Wrapper for Raspberry Pi OS (Debian 13 Trixie) KDE Edition
# Syncs the project from Windows (/mnt/c/...) into native WSL Linux ext4 (~/)
# while preserving the downloaded base image cache across builds, runs
# build-image.sh, and copies the finished .img / .img.xz to output/.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WSL_BUILD_DIR="${HOME}/RaspPi-KDE-Build"

# Resolve Windows output directories dynamically (no hardcoded usernames)
WIN_PROJECT_OUTPUT="${SCRIPT_DIR}/output"
WIN_DOWNLOADS_OUTPUT=""
if [[ "${SCRIPT_DIR}" == /mnt/c/Users/* ]]; then
    WIN_USER="$(echo "${SCRIPT_DIR}" | cut -d/ -f5)"
    if [ -n "${WIN_USER}" ] && [ -d "/mnt/c/Users/${WIN_USER}/Downloads" ]; then
        WIN_DOWNLOADS_OUTPUT="/mnt/c/Users/${WIN_USER}/Downloads/RaspPi-Build-Output"
    fi
fi

echo "======================================================================"
echo " 🚀 Step 1: Syncing project into native WSL Linux filesystem (${WSL_BUILD_DIR})..."
echo "======================================================================"
mkdir -p "${WSL_BUILD_DIR}"

# Ensure rsync is installed in WSL
if ! command -v rsync >/dev/null 2>&1; then
    sudo apt-get update -y && sudo apt-get install -y rsync
fi

# Sync scripts and configs while keeping cache/ so base image isn't re-downloaded every time
rsync -a --delete \
    --exclude 'work/' \
    --exclude 'output/' \
    --exclude 'cache/' \
    --exclude '.git/' \
    "${SCRIPT_DIR}/" "${WSL_BUILD_DIR}/"

cd "${WSL_BUILD_DIR}"
find . -type f -name "*.sh" -exec sed -i 's/\r$//' {} +
chmod +x build-image.sh build-wsl.sh build_wsl.sh verify-image.sh scripts/*.sh 2>/dev/null || true

echo "======================================================================"
echo " ⚡ Step 2: Running automated ARM64 chroot image build in WSL2..."
echo "======================================================================"
sudo ./build-image.sh "$@"

echo "======================================================================"
echo " 📦 Step 3: Copying finished .img to Windows output folders..."
echo "======================================================================"
mkdir -p "${WIN_PROJECT_OUTPUT}"
cp -v "${WSL_BUILD_DIR}/output/"*.img* "${WIN_PROJECT_OUTPUT}/" 2>/dev/null || true
cp -v "${WSL_BUILD_DIR}/output/"*.sha256 "${WIN_PROJECT_OUTPUT}/" 2>/dev/null || true

if [ -n "${WIN_DOWNLOADS_OUTPUT}" ]; then
    mkdir -p "${WIN_DOWNLOADS_OUTPUT}"
    cp -v "${WSL_BUILD_DIR}/output/"*.img* "${WIN_DOWNLOADS_OUTPUT}/" 2>/dev/null || true
    cp -v "${WSL_BUILD_DIR}/output/"*.sha256 "${WIN_DOWNLOADS_OUTPUT}/" 2>/dev/null || true
fi

echo "======================================================================"
echo " 🎉 BUILD COMPLETE!"
echo "    Saved to project folder : ${WIN_PROJECT_OUTPUT}"
if [ -n "${WIN_DOWNLOADS_OUTPUT}" ]; then
    echo "    Saved to Downloads      : ${WIN_DOWNLOADS_OUTPUT}"
fi
echo "======================================================================"
