# Qualcomm USB Userspace Driver — Windows

## Overview

This package contains the Qualcomm USB userspace drivers for Windows, which
provide logical representations of Qualcomm® chipset-enabled mobile devices
over USB using WinUSB (userspace communication). The drivers support x86,
x64 (amd64), ARM, and ARM64 architectures.

## Directory Structure

```
src/windows/
├── install.bat                # Installs all driver packages
├── uninstall.bat              # Removes all driver packages
├── qcfilter.inf / .cat        # USB composite device filter driver
├── qcmdmlib.inf / .cat        # WinUSB modem device driver
├── qcserlib.inf / .cat        # WinUSB serial device driver
├── qcwwanlib.inf / .cat       # WinUSB WWAN device driver
├── qcadb.inf / .cat           # WinUSB ADB device driver
├── qdblib.inf / .cat          # WinUSB QDB device driver
├── filter/                    # USB filter driver binaries
│   ├── i386/qcusbfilter.sys
│   ├── amd64/qcusbfilter.sys
│   ├── arm/qcusbfilter.sys
│   └── arm64/qcusbfilter.sys
└── README.md                  # This file
```

## Prerequisites

- Windows 10 or later
- Administrator privileges
- USB subsystem enabled

## Installation

Right-click `install.bat` and select **Run as administrator**, or from an
elevated Command Prompt:

```cmd
install.bat
```

The script uses `pnputil /add-driver` to install each `.inf` driver package
into the Windows driver store. Windows will automatically match these drivers
to connected Qualcomm USB devices.

## Uninstallation

Right-click `uninstall.bat` and select **Run as administrator**, or from an
elevated Command Prompt:

```cmd
uninstall.bat
```

The script enumerates the Windows driver store, finds the OEM driver packages
that match the shipped `.inf` files, and removes them with
`pnputil /delete-driver /uninstall /force`.

## Verifying Installation

List installed Qualcomm driver packages:

```cmd
pnputil /enum-drivers | findstr /i "qc"
```

Or check for a specific driver:

```cmd
pnputil /enum-drivers | findstr /i "qcmdmlib"
```

## Driver Packages

| INF File | Description |
|---|---|
| `qcfilter.inf` | USB composite device filter driver — routes child interfaces to the correct function drivers |
| `qcmdmlib.inf` | WinUSB modem (MDM) device driver |
| `qcserlib.inf` | WinUSB serial device driver |
| `qcwwanlib.inf` | WinUSB WWAN device driver |
| `qcadb.inf` | WinUSB ADB device driver |
| `qdblib.inf` | WinUSB QDB (Qualcomm Debug Bridge) device driver |

All drivers use WinUSB as the underlying function driver (`winusb.inf`) and
are signed with Microsoft-attested catalog (`.cat`) files.

## Known Limitations

- Device access conflicts may occur if the ADB service is active. To resolve
  Diag/ADB conflicts, stop the ADB service and reconnect the device.
- RMNET / QMI / MBN operations are not supported in userspace mode.