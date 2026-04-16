#!/bin/bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause
#
# Build script to create a Debian (.deb) package for the
# Qualcomm USB Userspace Driver.
#
# Usage: ./build_deb.sh [--output-dir <dir>]
#
# Output: qcom-usb-userspace-driver_<version>_all.deb

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"
OUTPUT_DIR="$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

###############################################################################
# Parse arguments
###############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--output-dir <dir>]"
            echo ""
            echo "Builds a Debian (.deb) package for the Qualcomm USB Userspace Driver."
            echo ""
            echo "Options:"
            echo "  --output-dir <dir>  Directory to write the .deb file (default: installer/)"
            echo "  -h, --help          Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h for help."
            exit 1
            ;;
    esac
done

###############################################################################
# Verify dependencies
###############################################################################

if ! command -v dpkg-deb &>/dev/null; then
    echo -e "${RED}Error: dpkg-deb is required but not installed.${RESET}"
    echo "Install it with: sudo apt install dpkg"
    exit 1
fi

###############################################################################
# Read version
###############################################################################

if [ ! -f "$VERSION_FILE" ]; then
    echo -e "${RED}Error: VERSION file not found at $VERSION_FILE${RESET}"
    exit 1
fi

RAW_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
if [ -z "$RAW_VERSION" ]; then
    echo -e "${RED}Error: VERSION file is empty.${RESET}"
    exit 1
fi

# Debian version: convert dots to dots (already compatible), ensure valid
DEB_VERSION="$RAW_VERSION"
PKG_NAME="qcom-usb-userspace-driver"
DEB_FILE="${PKG_NAME}_${DEB_VERSION}_all.deb"

STAGING_DIR=$(mktemp -d)
PKG_ROOT="$STAGING_DIR/${PKG_NAME}_${DEB_VERSION}_all"

echo ""
echo -e "${CYAN}========================================================================${RESET}"
echo -e "${BOLD}  Building Qualcomm USB Userspace Driver Debian Package${RESET}"
echo -e "${CYAN}========================================================================${RESET}"
echo ""
echo -e "  ${BOLD}Version:${RESET}     $DEB_VERSION"
echo -e "  ${BOLD}Package:${RESET}     $DEB_FILE"
echo -e "  ${BOLD}Output dir:${RESET}  $OUTPUT_DIR"
echo ""

###############################################################################
# Create package directory tree
###############################################################################

echo -e "  ${CYAN}[1/5]${RESET} Creating package directory tree..."

# Installed files
DEST="$PKG_ROOT/opt/qcom/qcom_userspace"
mkdir -p "$DEST"
mkdir -p "$PKG_ROOT/usr/share/doc/${PKG_NAME}"

# DEBIAN control directory
mkdir -p "$PKG_ROOT/DEBIAN"

###############################################################################
# Copy files
###############################################################################

echo -e "  ${CYAN}[2/5]${RESET} Copying driver files..."

# Core driver scripts
for f in qcom_userspace.sh qcom_drivers.sh QcDevDriver.sh; do
    if [ -f "$SRC_DIR/$f" ]; then
        cp "$SRC_DIR/$f" "$DEST/"
        chmod 755 "$DEST/$f"
    else
        echo -e "  ${RED}Warning: $f not found in $SRC_DIR — skipping.${RESET}"
    fi
done

# VERSION file
cp "$VERSION_FILE" "$DEST/VERSION"

# Documentation
if [ -f "$SRC_DIR/ReleaseNotes.txt" ]; then
    cp "$SRC_DIR/ReleaseNotes.txt" "$PKG_ROOT/usr/share/doc/${PKG_NAME}/"
fi
if [ -f "$SRC_DIR/README.md" ]; then
    cp "$SRC_DIR/README.md" "$PKG_ROOT/usr/share/doc/${PKG_NAME}/"
fi
cp "$SCRIPT_DIR/README.md" "$PKG_ROOT/usr/share/doc/${PKG_NAME}/INSTALL.md" 2>/dev/null || true

# Copyright / license placeholder
cat > "$PKG_ROOT/usr/share/doc/${PKG_NAME}/copyright" <<'EOFCOPYRIGHT'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: qcom-usb-userspace-driver
Upstream-Contact: https://github.com/qualcomm/qcom-usb-userspace-drivers

Files: *
Copyright: Qualcomm Technologies, Inc. and/or its subsidiaries.
License: BSD-3-Clause
EOFCOPYRIGHT

###############################################################################
# Create DEBIAN/control
###############################################################################

echo -e "  ${CYAN}[3/5]${RESET} Creating DEBIAN control files..."

# Calculate installed size in KB
INSTALLED_SIZE=$(du -sk "$PKG_ROOT" --exclude=DEBIAN 2>/dev/null | cut -f1)

cat > "$PKG_ROOT/DEBIAN/control" <<EOFCONTROL
Package: ${PKG_NAME}
Version: ${DEB_VERSION}
Section: utils
Priority: optional
Architecture: all
Installed-Size: ${INSTALLED_SIZE}
Maintainer: Qualcomm Innovation Center, Inc.
Conflicts: qcom-usb-drivers-dkms
Replaces: qcom-usb-drivers-dkms
Description: Qualcomm USB Userspace Driver
 Provides logical representations of Qualcomm chipset-enabled mobile devices
 over USB using libusb (userspace communication). Replaces the need for
 kernel-level QUD drivers for supported use cases.
 .
 Features:
  - Userspace USB communication via libusb
  - Automatic kernel module conflict resolution (qcserial blacklisting)
  - Udev rules for non-root device access
  - Supports upgrade, reinstall, and downgrade workflows
EOFCONTROL

###############################################################################
# Create DEBIAN/preinst (runs before unpack — removes conflicting packages)
###############################################################################

cat > "$PKG_ROOT/DEBIAN/preinst" <<'EOFPREINST'
#!/bin/bash
# Pre-installation script for qcom-usb-userspace-driver
# Removes conflicting kernel-space driver packages before dpkg unpacks files.
set -e

case "$1" in
    install|upgrade)
        # --- Unload DKMS-built kernel modules ---
        for mod in qcom-serial qcom_usbnet qcom_usb qtiDevInf; do
            mod_under=$(echo "$mod" | tr '-' '_')
            if lsmod | grep -q "^${mod_under}"; then
                echo "Unloading kernel module: $mod"
                rmmod "$mod" 2>/dev/null || true
            fi
        done

        # --- Clean up any leftover DKMS registrations ---
        if command -v dkms >/dev/null 2>&1; then
            for entry in $(dkms status 2>/dev/null | grep -i "qcom-usb-drivers" | awk -F'[,:]' '{print $1 "/" $2}' | tr -d ' '); do
                echo "Removing DKMS registration: $entry"
                dkms remove "$entry" --all 2>/dev/null || true
            done
        fi

        # --- Remove legacy QTI installation ---
        if [ -d /opt/QTI/QUD ]; then
            echo "Removing legacy QTI QUD installation..."
            if [ -f /opt/QTI/QUD/QcDevDriver.sh ]; then
                bash /opt/QTI/QUD/QcDevDriver.sh uninstall 2>/dev/null || true
            fi
            rm -rf /opt/QTI/QUD
        fi

        # --- Stop legacy systemd services ---
        for svc in qcom-qud QUDService; do
            if systemctl is-active --quiet "$svc" 2>/dev/null; then
                systemctl stop "$svc" 2>/dev/null || true
            fi
            if [ -f "/etc/systemd/system/${svc}.service" ]; then
                systemctl disable "$svc" 2>/dev/null || true
                rm -f "/etc/systemd/system/${svc}.service"
            fi
        done
        systemctl daemon-reload 2>/dev/null || true

        echo "Pre-installation cleanup complete."
        ;;
esac

exit 0
EOFPREINST
chmod 755 "$PKG_ROOT/DEBIAN/preinst"

###############################################################################
# Create DEBIAN/postinst (runs after install)
###############################################################################

cat > "$PKG_ROOT/DEBIAN/postinst" <<'EOFPOSTINST'
#!/bin/bash
# Post-installation script for qcom-usb-userspace-driver
set -e

QCOM_DEST=/opt/qcom/qcom_userspace
MODULE_BLACKLIST_CONFIG=/etc/modprobe.d
MODULE_BLACKLIST_PATH="/lib/modules/$(uname -r)/kernel/drivers/usb/serial"

case "$1" in
    configure)
        # Record installed version
        if [ -f "$QCOM_DEST/VERSION" ]; then
            cp "$QCOM_DEST/VERSION" "$QCOM_DEST/.version"
        fi

        # --- Remove conflicting QUD kernel drivers (manual install) if present ---
        QCOM_USB_DRIVER_PATH="/lib/modules/$(uname -r)/kernel/drivers/usb/misc"
        QCOM_USBNET_DRIVER_PATH="/lib/modules/$(uname -r)/kernel/drivers/net/usb"
        if [ -f "$QCOM_USBNET_DRIVER_PATH/qcom_usbnet.ko" ] || \
           [ -f "$QCOM_USB_DRIVER_PATH/qcom_usb.ko" ]; then
            if [ -f "$QCOM_DEST/qcom_drivers.sh" ]; then
                bash "$QCOM_DEST/qcom_drivers.sh" uninstall 2>/dev/null || true
            fi
        fi

        # --- Blacklist qcserial ---
        if [ -f "$MODULE_BLACKLIST_CONFIG/blacklist.conf" ]; then
            if ! grep -q 'blacklist qcserial' "$MODULE_BLACKLIST_CONFIG/blacklist.conf" 2>/dev/null; then
                echo "blacklist qcserial" >> "$MODULE_BLACKLIST_CONFIG/blacklist.conf"
                echo "install qcserial /bin/false" >> "$MODULE_BLACKLIST_CONFIG/blacklist.conf"
            fi
        else
            echo "blacklist qcserial" > "$MODULE_BLACKLIST_CONFIG/blacklist.conf"
            echo "install qcserial /bin/false" >> "$MODULE_BLACKLIST_CONFIG/blacklist.conf"
        fi
        chmod 644 "$MODULE_BLACKLIST_CONFIG/blacklist.conf"

        # Rename qcserial.ko if present
        if [ -f "$MODULE_BLACKLIST_PATH/qcserial.ko" ]; then
            mv "$MODULE_BLACKLIST_PATH/qcserial.ko" "$MODULE_BLACKLIST_PATH/qcserial_dup"
        fi

        depmod 2>/dev/null || true

        # --- Udev rules ---
        UDEV_RULE='SUBSYSTEM=="usb", ATTR{idVendor}=="05c6", MODE="0666", GROUP="plugdev"'
        echo "$UDEV_RULE" > /etc/udev/rules.d/99-qcom-userspace.rules
        udevadm control --reload-rules 2>/dev/null || true
        udevadm trigger 2>/dev/null || true

        # --- Userspace config ---
        cat > /etc/qcom_libusb.conf <<EOFCONF
QCOM_USERSPACE_SUPPORT=1
QCOM_LIBUSB_SUPPORT=1
EOFCONF

        echo "Qualcomm USB Userspace Driver v$(cat "$QCOM_DEST/VERSION" 2>/dev/null) installed successfully."
        ;;
esac

exit 0
EOFPOSTINST
chmod 755 "$PKG_ROOT/DEBIAN/postinst"

###############################################################################
# Create DEBIAN/prerm (runs before removal)
###############################################################################

cat > "$PKG_ROOT/DEBIAN/prerm" <<'EOFPRERM'
#!/bin/bash
# Pre-removal script for qcom-usb-userspace-driver
set -e

case "$1" in
    remove|purge)
        # Stop systemd services if present
        for svc in qcom-qud.service QUDService.service; do
            if systemctl is-active --quiet "${svc%.service}" 2>/dev/null; then
                systemctl stop "${svc%.service}" 2>/dev/null || true
            fi
            if [ -f "/etc/systemd/system/$svc" ]; then
                systemctl disable "$svc" 2>/dev/null || true
                rm -f "/etc/systemd/system/$svc"
            fi
        done
        systemctl daemon-reload 2>/dev/null || true
        ;;
esac

exit 0
EOFPRERM
chmod 755 "$PKG_ROOT/DEBIAN/prerm"

###############################################################################
# Create DEBIAN/postrm (runs after removal)
###############################################################################

cat > "$PKG_ROOT/DEBIAN/postrm" <<'EOFPOSTRM'
#!/bin/bash
# Post-removal script for qcom-usb-userspace-driver
set -e

MODULE_BLACKLIST_CONFIG=/etc/modprobe.d
MODULE_BLACKLIST_PATH="/lib/modules/$(uname -r)/kernel/drivers/usb/serial"

case "$1" in
    remove|purge)
        # --- Remove udev rules ---
        rm -f /etc/udev/rules.d/99-qcom-userspace.rules
        udevadm control --reload-rules 2>/dev/null || true
        udevadm trigger 2>/dev/null || true

        # --- Remove config ---
        rm -f /etc/qcom_libusb.conf
        rm -f /dev/QCOM_USERSPACE* /dev/QCOM_LIBUSB* 2>/dev/null || true

        # --- Restore qcserial ---
        if [ -f "$MODULE_BLACKLIST_CONFIG/blacklist.conf" ]; then
            if grep -q 'qcserial' "$MODULE_BLACKLIST_CONFIG/blacklist.conf" 2>/dev/null; then
                sed -i '/qcserial/d' "$MODULE_BLACKLIST_CONFIG/blacklist.conf"
            fi
            chmod 644 "$MODULE_BLACKLIST_CONFIG/blacklist.conf"
        fi

        if [ -f "$MODULE_BLACKLIST_PATH/qcserial_dup" ]; then
            mv "$MODULE_BLACKLIST_PATH/qcserial_dup" "$MODULE_BLACKLIST_PATH/qcserial.ko"
        fi

        depmod 2>/dev/null || true

        # --- Remove version file and directory ---
        rm -f /opt/qcom/qcom_userspace/.version
        rmdir /opt/qcom/qcom_userspace 2>/dev/null || true
        rmdir /opt/qcom 2>/dev/null || true

        echo "Qualcomm USB Userspace Driver uninstalled successfully."
        ;;
esac

exit 0
EOFPOSTRM
chmod 755 "$PKG_ROOT/DEBIAN/postrm"

###############################################################################
# Build the .deb
###############################################################################

echo -e "  ${CYAN}[4/5]${RESET} Building .deb package..."

mkdir -p "$OUTPUT_DIR"
dpkg-deb --build "$PKG_ROOT" "$OUTPUT_DIR/$DEB_FILE"

###############################################################################
# Cleanup & summary
###############################################################################

echo -e "  ${CYAN}[5/5]${RESET} Cleaning up staging directory..."
rm -rf "$STAGING_DIR"

DEB_PATH="$OUTPUT_DIR/$DEB_FILE"
if [ -f "$DEB_PATH" ]; then
    DEB_SIZE=$(du -h "$DEB_PATH" | cut -f1)
    echo ""
    echo -e "${GREEN}  Build successful!${RESET}"
    echo ""
    echo -e "  ${BOLD}Output:${RESET}  $DEB_PATH"
    echo -e "  ${BOLD}Size:${RESET}    $DEB_SIZE"
    echo ""
    echo -e "  ${BOLD}Install:${RESET}   sudo dpkg -i $DEB_FILE"
    echo -e "  ${BOLD}Uninstall:${RESET} sudo dpkg -r ${PKG_NAME}"
    echo -e "  ${BOLD}Info:${RESET}      dpkg -I $DEB_FILE"
    echo -e "  ${BOLD}Contents:${RESET}  dpkg -c $DEB_FILE"
    echo ""

    # Show package info
    echo -e "  ${CYAN}Package info:${RESET}"
    dpkg-deb --info "$DEB_PATH" 2>/dev/null | sed 's/^/    /'
    echo ""
else
    echo -e "${RED}  Build failed — .deb file not created.${RESET}"
    exit 1
fi