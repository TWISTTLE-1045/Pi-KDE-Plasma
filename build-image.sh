#!/usr/bin/env bash
# ==============================================================================
# Automated ARM64 Chroot Image Builder for Raspberry Pi 5 (4GB RAM) — WSL2 Ready
# Target OS: Raspberry Pi OS Lite (Debian 13 Trixie, arm64) + KDE Plasma Wayland
# First-Boot: 100% Native KDE plasma-initial-setup OEM Wizard (No GTK piwiz)
# ==============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${PROJECT_ROOT}/work"
CACHE_DIR="${PROJECT_ROOT}/cache"
OUTPUT_DIR="${PROJECT_ROOT}/output"
ROOTFS_MNT="${WORK_DIR}/rootfs"

IMG_VERSION_DATE="$(date +%Y-%m-%d)"
OUTPUT_IMG_NAME="RaspberryPiOS-13-Trixie-KDE-Plasma-arm64-${IMG_VERSION_DATE}.img"
BASE_IMG_URL="https://downloads.raspberrypi.com/raspios_lite_arm64_latest"
CUSTOM_BASE_IMG=""
COMPRESS_XZ=0
EXPAND_SIZE_GB=6
RESUME_BUILD=0

LOOP_DEV=""
USED_KPARTX=0

# Parse CLI flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-image)
            CUSTOM_BASE_IMG="$2"
            shift 2
            ;;
        --compress|-z)
            COMPRESS_XZ=1
            shift
            ;;
        --resume|-r)
            RESUME_BUILD=1
            shift
            ;;
        --expand-gb)
            EXPAND_SIZE_GB="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
Usage: sudo ./build-image.sh [OPTIONS]

Options:
  --base-image <path>   Path to local Raspberry Pi OS Lite arm64 .img or .img.xz
  --expand-gb <size>    Additional GB to add to root partition (default: 6)
  --resume, -r          Resume from existing work/working-raspios-trixie-arm64.img
  --compress, -z        Also compress final .img into .img.xz for faster flashing
  --help, -h            Show this help message
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Ensure script is executed as root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Please run this script with sudo: sudo ./build-image.sh"
    exit 1
fi

# Warn if running directly on a Windows NTFS mount (/mnt/c/...)
if [[ "${PROJECT_ROOT}" == /mnt/* ]]; then
    echo "⚠️  WARNING: You are running inside a Windows NTFS mount (${PROJECT_ROOT})."
    echo "    Linux chroot permissions and loop mounts MUST run on native WSL ext4."
    echo "    Please run ./build-wsl.sh (or ./build_wsl.sh) instead!"
    exit 1
fi

# Cleanup trap to safely unmount chroot and detach loop devices on exit/failure
cleanup() {
    set +e
    echo "==> Cleaning up mounts and loop devices..."
    if mountpoint -q "${ROOTFS_MNT}/boot/firmware" 2>/dev/null; then
        umount -lf "${ROOTFS_MNT}/boot/firmware"
    fi
    if mountpoint -q "${ROOTFS_MNT}/boot" 2>/dev/null; then
        umount -lf "${ROOTFS_MNT}/boot"
    fi
    for mp in dev/pts dev proc sys run; do
        if mountpoint -q "${ROOTFS_MNT}/${mp}" 2>/dev/null; then
            umount -lf "${ROOTFS_MNT}/${mp}"
        fi
    done
    if mountpoint -q "${ROOTFS_MNT}" 2>/dev/null; then
        sync
        umount -lf "${ROOTFS_MNT}"
    fi
    if [ -n "${LOOP_DEV}" ]; then
        if [ "${USED_KPARTX}" -eq 1 ]; then
            kpartx -dv "${LOOP_DEV}" 2>/dev/null || true
        fi
        losetup -d "${LOOP_DEV}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "======================================================================"
echo " 🍓 Raspberry Pi 5 KDE Plasma (Trixie arm64) Automated Image Builder"
echo "======================================================================"

# Step 0: Sanitize CRLF line endings across all text scripts & config files (excluding binary images)
find "${PROJECT_ROOT}/scripts" "${PROJECT_ROOT}/configs" -type f ! -name "*.png" ! -name "*.jpg" -exec sed -i 's/\r$//' {} + 2>/dev/null || true
sed -i 's/\r$//' "${PROJECT_ROOT}/verify-image.sh" 2>/dev/null || true
chmod +x "${PROJECT_ROOT}/verify-image.sh" "${PROJECT_ROOT}/scripts/"*.sh

# Step 1: Check and install required host build packages (WSL2 + Ubuntu/Debian)
echo "==> Checking host build dependencies..."
HOST_DEPS=(
    qemu-user
    qemu-user-binfmt
    parted
    kpartx
    e2fsprogs
    dosfstools
    xz-utils
    curl
    ca-certificates
    rsync
    fdisk
    git
)
MISSING_DEPS=()
for pkg in "${HOST_DEPS[@]}"; do
    if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
        MISSING_DEPS+=("${pkg}")
    fi
done
if [ "${#MISSING_DEPS[@]}" -gt 0 ]; then
    echo "==> Installing missing host packages: ${MISSING_DEPS[*]}"
    apt-get update -y
    apt-get install -y "${MISSING_DEPS[@]}" || apt-get install -y qemu-user-static binfmt-support parted kpartx e2fsprogs dosfstools xz-utils curl ca-certificates rsync fdisk git
fi

# Ensure binfmt_misc is mounted and QEMU aarch64 handler is active (WSL2 safe)
if [ ! -d /proc/sys/fs/binfmt_misc ]; then
    modprobe binfmt_misc 2>/dev/null || true
fi
if [ ! -f /proc/sys/fs/binfmt_misc/register ]; then
    mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
fi
if [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    systemctl restart systemd-binfmt 2>/dev/null || true
    update-binfmts --enable qemu-aarch64 2>/dev/null || true
fi
# Direct binfmt_misc registration fallback for WSL2 instances without systemd-binfmt
if [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ] && [ -f /proc/sys/fs/binfmt_misc/register ]; then
    echo ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:F' \
        > /proc/sys/fs/binfmt_misc/register 2>/dev/null || true
fi
echo "✓ QEMU aarch64 binfmt_misc handler is ready."

mkdir -p "${WORK_DIR}" "${CACHE_DIR}" "${OUTPUT_DIR}" "${ROOTFS_MNT}"

# Detach any stale loop devices pointing to WORKING_IMG
WORKING_IMG="${WORK_DIR}/working-raspios-trixie-arm64.img"
for stale_loop in $(losetup -j "${WORKING_IMG}" | cut -d: -f1); do
    losetup -d "${stale_loop}" 2>/dev/null || true
done

# Step 2: Acquire Base Raspberry Pi OS Lite (arm64) Image
if [ "${RESUME_BUILD}" -eq 1 ] && [ -f "${WORKING_IMG}" ]; then
    echo "✓ Resuming from existing working image: ${WORKING_IMG}"
else
    rm -f "${WORKING_IMG}"
    if [ -n "${CUSTOM_BASE_IMG}" ]; then
        if [ ! -f "${CUSTOM_BASE_IMG}" ]; then
            echo "❌ Specified base image not found: ${CUSTOM_BASE_IMG}"
            exit 1
        fi
        echo "==> Using local base image: ${CUSTOM_BASE_IMG}"
        if [[ "${CUSTOM_BASE_IMG}" == *.xz ]]; then
            xz -dkc "${CUSTOM_BASE_IMG}" > "${WORKING_IMG}"
        else
            cp -f "${CUSTOM_BASE_IMG}" "${WORKING_IMG}"
        fi
    else
        CACHED_XZ="${CACHE_DIR}/raspios-lite-arm64-latest.img.xz"
        if [ ! -f "${CACHED_XZ}" ]; then
            echo "==> Downloading latest official Raspberry Pi OS Lite (64-bit / arm64) image..."
            curl -fL "${BASE_IMG_URL}" -o "${CACHED_XZ}"
        else
            echo "✓ Using cached base image archive: ${CACHED_XZ}"
        fi
        echo "==> Extracting base image to ${WORKING_IMG}..."
        xz -dkc "${CACHED_XZ}" > "${WORKING_IMG}"
    fi

    # Step 3: Expand image file and grow rootfs partition
    echo "==> Expanding image by +${EXPAND_SIZE_GB}GB for KDE Plasma installation..."
    truncate -s "+${EXPAND_SIZE_GB}G" "${WORKING_IMG}"
    parted -s "${WORKING_IMG}" resizepart 2 100%
fi

echo "==> Attaching image to loop device (WSL2 & Linux compatible)..."
LOOP_DEV="$(losetup -Pf --show "${WORKING_IMG}")"
partprobe "${LOOP_DEV}" 2>/dev/null || true
partx -u "${LOOP_DEV}" 2>/dev/null || true
sleep 1

BOOT_PART="${LOOP_DEV}p1"
ROOT_PART="${LOOP_DEV}p2"

# Fallback to kpartx if WSL2 kernel did not create /dev/loopXp1 and /dev/loopXp2
if [ ! -b "${ROOT_PART}" ]; then
    echo "==> Using kpartx device-mapper for loop partitions in WSL2..."
    kpartx -av "${LOOP_DEV}"
    USED_KPARTX=1
    sleep 1
    LOOP_NAME="$(basename "${LOOP_DEV}")"
    BOOT_PART="/dev/mapper/${LOOP_NAME}p1"
    ROOT_PART="/dev/mapper/${LOOP_NAME}p2"
fi

echo "==> Checking and resizing ext4 root filesystem (${ROOT_PART})..."
e2fsck -fy "${ROOT_PART}" || true
resize2fs "${ROOT_PART}"

# Step 4: Mount rootfs, boot partition, and virtual filesystems
echo "==> Mounting rootfs and boot partition..."
mount -o rw "${ROOT_PART}" "${ROOTFS_MNT}"
mkdir -p "${ROOTFS_MNT}/boot/firmware"
mount -o rw "${BOOT_PART}" "${ROOTFS_MNT}/boot/firmware"

# Copy QEMU static binary into target rootfs
if [ -f /usr/bin/qemu-aarch64-static ]; then
    cp -f /usr/bin/qemu-aarch64-static "${ROOTFS_MNT}/usr/bin/qemu-aarch64-static"
elif [ -f /usr/bin/qemu-aarch64 ]; then
    cp -f /usr/bin/qemu-aarch64 "${ROOTFS_MNT}/usr/bin/qemu-aarch64"
    cp -f /usr/bin/qemu-aarch64 "${ROOTFS_MNT}/usr/bin/qemu-aarch64-static"
fi

# Preserve DNS resolution inside chroot
if [ -L "${ROOTFS_MNT}/etc/resolv.conf" ] || [ -f "${ROOTFS_MNT}/etc/resolv.conf" ]; then
    mv -f "${ROOTFS_MNT}/etc/resolv.conf" "${ROOTFS_MNT}/etc/resolv.conf.bak" 2>/dev/null || true
fi
cp -L /etc/resolv.conf "${ROOTFS_MNT}/etc/resolv.conf"

# Ensure APT sources point to Debian 13 (Trixie) arm64
echo "==> Ensuring APT sources inside rootfs target Debian 13 (Trixie) arm64..."
if [ -f "${ROOTFS_MNT}/etc/apt/sources.list" ]; then
    sed -i 's/bookworm/trixie/g' "${ROOTFS_MNT}/etc/apt/sources.list" 2>/dev/null || true
fi
find "${ROOTFS_MNT}/etc/apt/sources.list.d" -type f -exec sed -i 's/bookworm/trixie/g' {} + 2>/dev/null || true

# Stage build scripts and configs into chroot /tmp/rpi-kde-build
mkdir -p "${ROOTFS_MNT}/tmp/rpi-kde-build"
cp -r "${PROJECT_ROOT}/configs" "${PROJECT_ROOT}/scripts" "${PROJECT_ROOT}/verify-image.sh" \
    "${ROOTFS_MNT}/tmp/rpi-kde-build/"
chmod +x "${ROOTFS_MNT}/tmp/rpi-kde-build/verify-image.sh" \
         "${ROOTFS_MNT}/tmp/rpi-kde-build/scripts/"*.sh

# Bind-mount virtual filesystems
mount --bind /dev "${ROOTFS_MNT}/dev"
mount --bind /dev/pts "${ROOTFS_MNT}/dev/pts"
mount -t proc proc "${ROOTFS_MNT}/proc"
mount -t sysfs sysfs "${ROOTFS_MNT}/sys"
mount --bind /run "${ROOTFS_MNT}/run"

# Step 5: Execute chroot provisioning script
echo "==> Entering ARM64 chroot to install KDE Plasma & OEM First-Boot setup..."
chroot "${ROOTFS_MNT}" /usr/bin/env \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    /tmp/rpi-kde-build/scripts/chroot-setup.sh

# Step 6: Run pre-pack verification inside chroot
echo "==> Running pre-pack verification inside chroot..."
chroot "${ROOTFS_MNT}" /tmp/rpi-kde-build/verify-image.sh /

# Remove staged build directory and restore resolv.conf
rm -rf "${ROOTFS_MNT}/tmp/rpi-kde-build"
if [ -e "${ROOTFS_MNT}/etc/resolv.conf.bak" ]; then
    mv -f "${ROOTFS_MNT}/etc/resolv.conf.bak" "${ROOTFS_MNT}/etc/resolv.conf"
fi
rm -f "${ROOTFS_MNT}/usr/bin/qemu-aarch64-static" "${ROOTFS_MNT}/usr/bin/qemu-aarch64"

# Step 7: Unmount cleanly and finalize image
if [ "${COMPRESS_XZ}" -eq 1 ]; then
    echo "==> Zero-filling unused rootfs blocks for optimal .img.xz compression..."
    dd if=/dev/zero of="${ROOTFS_MNT}/zero.fill" bs=16M status=none 2>/dev/null || true
    rm -f "${ROOTFS_MNT}/zero.fill"
fi

echo "==> Unmounting chroot filesystems..."
sync
umount -lf "${ROOTFS_MNT}/boot/firmware"
for mp in dev/pts dev proc sys run; do
    umount -lf "${ROOTFS_MNT}/${mp}"
done
umount -lf "${ROOTFS_MNT}"

echo "==> Running final filesystem check on ${ROOT_PART}..."
e2fsck -fy "${ROOT_PART}" || true

if [ "${USED_KPARTX}" -eq 1 ]; then
    kpartx -dv "${LOOP_DEV}" 2>/dev/null || true
    USED_KPARTX=0
fi
losetup -d "${LOOP_DEV}"
LOOP_DEV=""

FINAL_IMG="${OUTPUT_DIR}/${OUTPUT_IMG_NAME}"
mv -f "${WORKING_IMG}" "${FINAL_IMG}"

echo "==> Generating SHA256 checksum..."
(cd "${OUTPUT_DIR}" && sha256sum "${OUTPUT_IMG_NAME}" > "${OUTPUT_IMG_NAME}.sha256")

if [ "${COMPRESS_XZ}" -eq 1 ]; then
    echo "==> Compressing image with xz -T0 (multi-threaded)..."
    xz -zkf -T0 "${FINAL_IMG}"
    (cd "${OUTPUT_DIR}" && sha256sum "${OUTPUT_IMG_NAME}.xz" > "${OUTPUT_IMG_NAME}.xz.sha256")
fi

echo "======================================================================"
echo " 🎉 BUILD COMPLETE!"
echo "    Output Image : ${FINAL_IMG}"
if [ "${COMPRESS_XZ}" -eq 1 ]; then
    echo "    Compressed   : ${FINAL_IMG}.xz"
fi
echo "======================================================================"
