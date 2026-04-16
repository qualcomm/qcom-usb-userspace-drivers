# Qualcomm USB Userspace Driver — Linux

## Overview

This package installs the Qualcomm USB userspace driver, which provides logical
representations of Qualcomm® chipset-enabled mobile devices over USB using
libusb (userspace communication). It replaces the need for kernel-level QUD
drivers for supported use cases.

## Directory Structure

```
src/linux/
├── installer/
│   ├── build_deb.sh      # Build script to create the .deb package
│   └── VERSION           # Package version identifier
├── qcom_userspace.sh     # Core userspace driver script
├── qcom_drivers.sh       # QUD kernel driver helper
├── QcDevDriver.sh        # Legacy QTI driver helper
├── ReleaseNotes.txt      # Detailed release history
└── README.md             # This file
```

## Prerequisites

- Linux (Ubuntu 20.04+, Debian 11+, or compatible)
- Root / sudo access
- USB subsystem enabled
- `dpkg-deb` (included with `dpkg`, standard on Debian/Ubuntu)

## Building the Debian Package

```bash
cd installer
./build_deb.sh
```

Options:
- `--output-dir <dir>` — Specify output directory (default: current directory)
- `-h`, `--help` — Show help

This produces `qcom-usb-userspace-driver_<version>_all.deb`.

## Installation

```bash
sudo dpkg -i qcom-usb-userspace-driver_<version>_all.deb
```

The package will:
- Detect and remove the conflicting kernel-space deb package (`qcom-usb-drivers-dkms`) if installed
- Remove any conflicting QUD kernel drivers or legacy QTI drivers (manual installs)
- Unload DKMS-built kernel modules (`qtiDevInf`, `qcom_usb`, `qcom_usbnet`, `qcom-serial`) and clean up DKMS registrations
- Blacklist the `qcserial` kernel module to avoid conflicts
- Create udev rules granting non-root users access to Qualcomm USB devices (`05c6` vendor)
- Enable userspace (libusb) communication via config file
- Record the installed version

## Uninstallation

```bash
sudo dpkg -r qcom-usb-userspace-driver
```

Or to purge (remove config files as well):

```bash
sudo dpkg -P qcom-usb-userspace-driver
```

The package removal will:
- Stop and remove systemd services if present
- Remove udev rules
- Restore the `qcserial` kernel module
- Remove blacklist entries
- Clean up configuration and device files

Confirm the package is removed:

```bash
dpkg -l | grep qcom-usb-userspace-driver
```

## Checking Installed Version

```bash
# Method 1: Using dpkg
dpkg -s qcom-usb-userspace-driver | grep Version

# Method 2: Read the version file directly
cat /opt/qcom/qcom_userspace/.version
```

## Upgrade / Downgrade

Install a newer or older `.deb` over the existing one:

```bash
sudo dpkg -i qcom-usb-userspace-driver_<new-version>_all.deb
```

`dpkg` will automatically run the pre-removal script for the old version and
the post-install script for the new version.

## Installed Files

| Path | Description |
|---|---|
| `/opt/qcom/qcom_userspace/` | Driver scripts and version file |
| `/etc/udev/rules.d/99-qcom-userspace.rules` | Udev rules for device access |
| `/etc/qcom_libusb.conf` | Userspace communication config |
| `/etc/modprobe.d/blacklist.conf` | qcserial blacklist entries (appended) |

## Known Limitations

- Currently supports communication with one device / one interface at a time,
  limiting multi-device usage.
- Device access conflicts may occur if the ADB service is active. This is a
  known limitation of libusb. To resolve Diag/ADB conflicts, detach the ADB
  service and then reconnect the device.
- RMNET / QMI / MBN operations are not supported in userspace mode.
