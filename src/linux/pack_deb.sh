#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# pack_deb.sh
# Builds a .deb package that installs Qualcomm userspace driver helper scripts
# and runs qcom_userspace.sh automatically upon installation.
#
# Source scripts expected in: ./build/
#   - qcom_userspace.sh
#   - qcom_drivers.sh
#   - QcDevDriver.sh
#
# Output .deb: ./build/<pkg>_<version>_<arch>.deb
#
# Usage:
#   ./pack_deb.sh
#
# Customization via env vars:
#   PKG_NAME    (default: Qualcomm_Userspace_Driver)
#   VERSION     (default: 1.0.0)
#   ARCH        (default: all)
#   MAINTAINER  (default: "Maintainer <maintainer@example.com>")
#   DESCRIPTION (default: generic description)
#   INSTALL_PREFIX (default: /opt/qcom/QUD_Userspace)
#   OUTPUT_DIR  (default: ./build)
#   NO_CLEANUP=1 to keep build workdir for inspection
# 
# Verify the payload in debian package:
# dpkg-deb -c build/qualcomm-userspace-driver_1.00.1.3_linux-anycpu.deb | grep -E
#  'qcom_userspace.sh|qcom_drivers.sh|QcDevDriver.sh'
#
# Uninstall the .deb package:
# sudo dpkg -r qualcomm-userspace-driver
# or
# sudo apt remove qualcomm-userspace-driver
# or
# sudo apt purge qualcomm-userspace-driver
#
# Purge package metadata and config files:
# sudo dpkg -P qualcomm-userspace-driver
# 
# Confirm the package is removed:
# dpkg -I | grep qualcomm-userspace-driver
# -----------------------------------------------------------------------------

#PKG_NAME="${PKG_NAME:-Qualcomm_Userspace_Driver}"
PKG_NAME="${PKG_NAME:-qualcomm-userspace-driver}"
VERSION="${VERSION:-1.00.1.6}"
#ARCH="${ARCH:-Linux-AnyCPU}"
ARCH="${ARCH:-linux-anycpu}"
MAINTAINER="${MAINTAINER:-Maintainer <maintainer@example.com>}"
DESCRIPTION="${DESCRIPTION:-Qualcomm userspace driver enabler for QUD devices. Installs helper scripts and executes qcom_userspace.sh during installation to enable userspace communication.}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/qcom/QUD_Userspace}"
OPTION_ZIP=$1
#ECCN Request: 3D991
#OSR Link: https://jira-dc4.qualcomm.com/jira/browse/OSR-18776

# Resolve directories relative to this script
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$BASE_DIR/build"
OUTPUT_DIR="${OUTPUT_DIR:-$BASE_DIR/build}"

# Compute valid Debian architecture for control file while preserving filename label
DEB_ARCH="$ARCH"
case "$(echo "$ARCH" | tr '[:upper:]' '[:lower:]')" in
  linux-anycpu|anycpu|any|noarch|all)
    DEB_ARCH="all"
    ;;
  x86_64|x64|amd64)
    DEB_ARCH="amd64"
    ;;
  aarch64|arm64)
    DEB_ARCH="arm64"
    ;;
  armhf)
    DEB_ARCH="armhf"
    ;;
  i386|x86)
    DEB_ARCH="i386"
    ;;
  *)
    # leave DEB_ARCH as provided; user may supply a valid Debian arch
    ;;
esac

# Pre-flight checks
if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "ERROR: dpkg-deb not found. Please run on a Debian/Ubuntu host with dpkg installed." >&2
  exit 1
fi

# Ensure source scripts exist
missing=0
for f in qcom_userspace.sh qcom_drivers.sh QcDevDriver.sh; do
  if [ ! -f "$SRC_DIR/$f" ]; then
    echo "ERROR: Missing required script: $SRC_DIR/$f" >&2
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  exit 1
fi

# Create working build directories
WORKDIR="$(mktemp -d -t "${PKG_NAME}-build-XXXXXX")"
BUILDROOT="$WORKDIR/${PKG_NAME}_${VERSION}"
trap 'if [ "${NO_CLEANUP:-0}" -ne 1 ]; then rm -rf "$WORKDIR"; else echo "Keeping workdir: $WORKDIR"; fi' EXIT

mkdir -p "$BUILDROOT/DEBIAN"
mkdir -p "$BUILDROOT$INSTALL_PREFIX"
mkdir -p "$OUTPUT_DIR"
chmod 0755 "$BUILDROOT$INSTALL_PREFIX"
chmod 0755 "$BUILDROOT/DEBIAN"

# Copy scripts into package payload and set permissions
install -m 0755 "$SRC_DIR/qcom_userspace.sh" "$BUILDROOT$INSTALL_PREFIX/qcom_userspace.sh"
install -m 0755 "$SRC_DIR/qcom_drivers.sh"    "$BUILDROOT$INSTALL_PREFIX/qcom_drivers.sh"
install -m 0755 "$SRC_DIR/QcDevDriver.sh"     "$BUILDROOT$INSTALL_PREFIX/QcDevDriver.sh"

# Create DEBIAN/control
cat > "$BUILDROOT/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: $DEB_ARCH
Maintainer: $MAINTAINER
Depends: bash, coreutils, sed, grep, udev, kmod
Description: $DESCRIPTION
EOF
chmod 0644 "$BUILDROOT/DEBIAN/control"

# Create DEBIAN/preinst to delete older log file and create a new one before installation
cat > "$BUILDROOT/DEBIAN/preinst" <<'EOF'
#!/usr/bin/env bash
set -e

INSTALL_PREFIX="/opt/qcom/QUD_Userspace"
LOG_FILE="$INSTALL_PREFIX/qcom_userspace_install.log"

# Ensure target directory exists
mkdir -p "$INSTALL_PREFIX" || true

# Delete older file (if any) and create a new one
if [ -e "$LOG_FILE" ]; then
  rm -f "$LOG_FILE" || true
fi
touch "$LOG_FILE" || true
chmod 0644 "$LOG_FILE" || true

exit 0
EOF
chmod 0755 "$BUILDROOT/DEBIAN/preinst"

# Create DEBIAN/postinst that runs qcom_userspace.sh on install
cat > "$BUILDROOT/DEBIAN/postinst" <<'EOF'
#!/usr/bin/env bash
set -e

INSTALL_PREFIX="/opt/qcom/QUD_Userspace"
LOG_FILE="$INSTALL_PREFIX/qcom_userspace_install.log"

echo "[QUD_Userspace] Ensuring script permissions..."
chmod 0755 "$INSTALL_PREFIX/qcom_userspace.sh" \
            "$INSTALL_PREFIX/qcom_drivers.sh" \
            "$INSTALL_PREFIX/QcDevDriver.sh" || true

echo "[QUD_Userspace] Executing qcom_userspace.sh to enable userspace driver..." >> "$LOG_FILE" 2>&1
if [ -x "$INSTALL_PREFIX/qcom_userspace.sh" ]; then
  cd "$INSTALL_PREFIX" || true
  "$INSTALL_PREFIX/qcom_userspace.sh" install >> "$LOG_FILE" 2>&1 || echo "[QUD_Userspace] WARNING: qcom_userspace.sh returned non-zero exit." >> "$LOG_FILE" 2>&1
else
  echo "[QUD_Userspace] ERROR: $INSTALL_PREFIX/qcom_userspace.sh install not found." >> "$LOG_FILE" 2>&1
fi

exit 0
EOF
chmod 0755 "$BUILDROOT/DEBIAN/postinst"

cat > "$BUILDROOT/DEBIAN/prerm" <<'EOF'
#!/usr/bin/env bash
set -e
INSTALL_PREFIX="/opt/qcom/QUD_Userspace"
LOG_FILE="$INSTALL_PREFIX/qcom_userspace_install.log"

echo "#############################" >> "$LOG_FILE" 2>&1
echo "[QUD_Userspace] Running uninstall hook..." >> "$LOG_FILE" 2>&1
if [ -x "$INSTALL_PREFIX/qcom_userspace.sh" ]; then
  cd "$INSTALL_PREFIX" || true
  "$INSTALL_PREFIX/qcom_userspace.sh" uninstall >> "$LOG_FILE" 2>&1 || echo "[QUD_Userspace] WARNING: uninstall returned non-zero exit." >> "$LOG_FILE" 2>&1
else
  echo "[QUD_Userspace] ERROR: $INSTALL_PREFIX/qcom_userspace.sh uninstall not found." >> "$LOG_FILE" 2>&1
fi
exit 0
EOF
chmod 0755 "$BUILDROOT/DEBIAN/prerm"

# Build the .deb
OUTPUT_DEB="$OUTPUT_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo "Building package -> $OUTPUT_DEB"
if dpkg-deb --help 2>&1 | grep -q -- '--root-owner-group'; then
  dpkg-deb --build --root-owner-group "$BUILDROOT" "$OUTPUT_DEB"
else
  dpkg-deb --build "$BUILDROOT" "$OUTPUT_DEB"
fi

echo "Successfully built: $OUTPUT_DEB"
echo "Install with: sudo dpkg -i \"$OUTPUT_DEB\""
echo "Note: postinst will execute qcom_userspace.sh during installation."
ZIP_FOLDER=${PKG_NAME}_${VERSION}_${ARCH}

if [ "$OPTION_ZIP" == "zip" ]; then
  echo "compress package"
  mkdir -p ${ZIP_FOLDER}
  cp ./build/${PKG_NAME}_${VERSION}_${ARCH}.deb "${ZIP_FOLDER}/"
  cp ./build/README.md "${ZIP_FOLDER}/"
  cp ./build/ReleaseNotes.txt "${ZIP_FOLDER}/"
  zip -r "${ZIP_FOLDER}.zip" "${ZIP_FOLDER}"
  rm -rf "${ZIP_FOLDER}"
fi
