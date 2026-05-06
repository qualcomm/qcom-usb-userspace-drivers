# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause

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

PKG_NAME="${PKG_NAME:-qualcomm-userspace-driver}"
VERSION="${VERSION:-1.00.1.6}"
ARCH="${ARCH:-linux-anycpu}"
MAINTAINER="${MAINTAINER:-Maintainer <maintainer@example.com>}"
DESCRIPTION="${DESCRIPTION:-Qualcomm userspace driver enabler for QUD devices. Installs helper scripts and executes qcom_userspace.sh during installation to enable userspace communication.}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/qcom/QUD_Userspace}"

# Handle --version / -v query option (prints the version and exits)
case "${1:-}" in
  -v|--version|version)
    echo "$PKG_NAME $VERSION"
    exit 0
    ;;
esac

OPTION_ZIP="${1:-}"
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
Conflicts: qud
Replaces: qud
Breaks: qud
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

echo "[QUD_Userspace] Ensuring script permissions..." >> "$LOG_FILE" 2>&1
chmod 0755 "$INSTALL_PREFIX/qcom_userspace.sh" \
            "$INSTALL_PREFIX/qcom_drivers.sh" \
            "$INSTALL_PREFIX/QcDevDriver.sh" || true

# 'qud' kernel driver package is removed by dpkg itself before postinst runs,
# via the Conflicts/Replaces/Breaks fields declared in DEBIAN/control.
# This stage will only display status and store dpkg events in the install log.
{
  echo ""
  echo "=================================================================="
  echo "[QUD_Userspace] Checking qud kernel driver state"
  echo "=================================================================="
} >> "$LOG_FILE" 2>&1

QUD_STATUS_RAW="$(dpkg-query -W -f='${Status}|${Version}' qud 2>/dev/null || true)"
QUD_STATUS_FIELD="${QUD_STATUS_RAW%%|*}"
QUD_VERSION_FIELD="${QUD_STATUS_RAW##*|}"
QUD_DPKG_EVENT=""
QUD_DPKG_TAIL=""

if [ -r /var/log/dpkg.log ]; then
  CURRENT_TXN="$(awk '/ startup /{buf=""} {buf=buf $0 ORS} END{printf "%s", buf}' /var/log/dpkg.log 2>/dev/null || true)"
  if [ -n "$CURRENT_TXN" ]; then
    QUD_DPKG_EVENT="$(printf '%s' "$CURRENT_TXN" \
      | grep -E '(^.* (remove|purge) qud:|^.* status (config-files|not-installed|half-installed|half-configured) qud:)' \
      | tail -n 1 || true)"
  fi
fi

QUD_DPKG_TAIL=""
if [ -r /var/log/dpkg.log ]; then
  QUD_DPKG_TAIL="$(grep -E 'qud:all|qualcomm-userspace-driver' /var/log/dpkg.log 2>/dev/null | tail -n 15 || true)"
fi

case "$QUD_STATUS_FIELD" in
  "deinstall ok config-files"|"deinstall ok half-configured"|"deinstall ok half-installed")
      echo "[QUD_Userspace] qud ($QUD_VERSION_FIELD) was just removed by dpkg via Conflicts/Replaces/Breaks." >> "$LOG_FILE" 2>&1
      ;;
  *)
      if [ -n "$QUD_DPKG_EVENT" ]; then
          echo "[QUD_Userspace] qud was just removed by dpkg via Conflicts/Replaces/Breaks in current installation (from /var/log/dpkg.log: $QUD_DPKG_EVENT)." >> "$LOG_FILE" 2>&1
      else
          echo "[QUD_Userspace] qud driver was not installed this time, so dpkg Conflicts/Replaces/Breaks did not remove anything." >> "$LOG_FILE" 2>&1
      fi
      ;;
esac

# Append the last few relevant lines of /var/log/dpkg.log
if [ -n "$QUD_DPKG_TAIL" ]; then
  echo "" >> "$LOG_FILE" 2>&1
  echo "[QUD_Userspace] /var/log/dpkg.log excerpt (last few instances of qud / qualcomm-userspace-driver events from /var/log/dpkg.log):" >> "$LOG_FILE" 2>&1
  printf '%s\n' "$QUD_DPKG_TAIL" | sed 's/^/[dpkg logs] /' >> "$LOG_FILE" 2>&1
fi

# Uninstall any QUD driver installed via qpm-cli
{
  echo ""
  echo "=================================================================="
  echo "[QUD_Userspace] qpm-cli QUD uninstall (qud.internal / qud / qud.slt)"
  echo "=================================================================="
} >> "$LOG_FILE" 2>&1
if command -v qpm-cli >/dev/null 2>&1; then
  QUD_INTERNAL_VERSION="$(qpm-cli --info qud.internal 2>/dev/null | grep "Installed" | awk '{printf $4}')"
  QUD_EXTERNAL_VERSION="$(qpm-cli --info qud 2>/dev/null | grep "Installed" | awk '{printf $4}')"
  QUD_SLT_VERSION="$(qpm-cli --info qud.slt 2>/dev/null | grep "Installed" | awk '{printf $4}')"

  if [ -n "$QUD_INTERNAL_VERSION" ] || [ -n "$QUD_EXTERNAL_VERSION" ] || [ -n "$QUD_SLT_VERSION" ]; then
    if [ -n "$QUD_INTERNAL_VERSION" ]; then
      echo "[QUD_Userspace] Uninstalling qud.internal ($QUD_INTERNAL_VERSION) via qpm-cli..." >> "$LOG_FILE" 2>&1
      qpm-cli --uninstall qud.internal --silent --force >> "$LOG_FILE" 2>&1 || true
    fi
    if [ -n "$QUD_EXTERNAL_VERSION" ]; then
      echo "[QUD_Userspace] Uninstalling qud ($QUD_EXTERNAL_VERSION) via qpm-cli..." >> "$LOG_FILE" 2>&1
      qpm-cli --uninstall qud --silent --force >> "$LOG_FILE" 2>&1 || true
    fi
    if [ -n "$QUD_SLT_VERSION" ]; then
      echo "[QUD_Userspace] Uninstalling qud.slt ($QUD_SLT_VERSION) via qpm-cli..." >> "$LOG_FILE" 2>&1
      qpm-cli --uninstall qud.slt --silent --force >> "$LOG_FILE" 2>&1 || true
    fi
  else
    echo "[QUD_Userspace] The User hasn't installed QUD driver via qpm-cli" >> "$LOG_FILE" 2>&1
  fi
else
  echo "[QUD_Userspace] qpm-cli not available, skipping qpm-cli QUD uninstall." >> "$LOG_FILE" 2>&1
fi

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
