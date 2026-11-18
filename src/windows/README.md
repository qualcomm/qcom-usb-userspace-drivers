# Qualcomm USB Userspace Drivers — Windows Installer

**Package:** `qcom_usb_userspace_drivers_<arch>.exe` (one self-extracting installer per architecture: `x86`, `x64`, `arm64`)
**Version:** 1.0.2.3
**Supported OS:** Windows 10 / Windows 11 (x86, x64, ARM64)

---

## Overview

The installer is a single self-extracting executable — there is no separate "extract" step. Running it elevated will:

1. Remove any legacy driver packages previously installed via `qpm-cli` / `qsc-cli`.
2. Uninstall any existing Qualcomm USB Userspace Drivers installation.
3. Extract the embedded driver payload (INF files, pre-compiled filter driver, `qdinstall.exe`, `qdclr.exe`, and the `libusb` DLL) to the install directory.
4. Register and install all INF drivers.
5. Register and start the WWAN service, if present in the payload.
6. Register an uninstall entry under Windows "Apps & Features".

**Administrator privileges** are required — the installer's manifest requests elevation, so Windows will prompt for UAC consent if it isn't already running as admin.

Default install location:

```
C:\Program Files\Qualcomm\Qualcomm USB Drivers
```

---

## Installation

Pick the installer matching your system architecture and run it (double-click, or from an elevated Command Prompt):

```cmd
qcom_usb_userspace_drivers_x64.exe
```

This is equivalent to:

```cmd
qcom_usb_userspace_drivers_x64.exe -i
```

Expected output ends with:

```
Step 4/4: Installing driver...

Install completed successfully.

Please find the installation logs at: C:\ProgramData\Qualcomm\QUD\userspace_drivers_install_log_<timestamp>.txt
```

---

## Uninstallation

**Recommended:** Windows Settings → Apps → Installed apps → *Qualcomm USB Userspace Drivers* → Uninstall.

**Command line** (equivalent, run elevated):

```cmd
qcom_usb_userspace_drivers_x64.exe -u
```

This removes the installed drivers and deletes the install directory.

> Do not run the installer with `-x` — that option no longer exists on the top-level installer. The underlying `qdinstall.exe -u` is used internally during uninstall to avoid the installer deleting itself while still running.

---

## Checking the version

```cmd
qcom_usb_userspace_drivers_x64.exe -v
```

---

## Logs

Every install and uninstall run writes a timestamped log file to:

```
C:\ProgramData\Qualcomm\QUD\
```

- `userspace_drivers_install_log_<yyyyMMdd_HHmmss>.txt`
- `userspace_drivers_uninstall_log_<yyyyMMdd_HHmmss>.txt`

The log file path is also printed at the end of each run. Please attach the relevant log file when reporting installation issues.

---

## libusb

The installer bundles `libusb-1.0.dll` (v1.0.29) matching the installer's architecture under:

```
C:\Program Files\Qualcomm\Qualcomm USB Drivers\libusb\libusb-1.0.dll
```

---

## Advanced: `qdinstall.exe`

For troubleshooting, `qdinstall.exe` (installed alongside the drivers) can be run directly from the install directory:

```cmd
qdinstall.exe -i -p <path>   Install drivers from path
qdinstall.exe -u             Uninstall drivers (keeps installation files)
qdinstall.exe -x             Uninstall drivers and remove installation files
qdinstall.exe -v             Display version information
qdinstall.exe -g             Print the registered installation path
```

This tool is invoked automatically by the top-level installer and normally does not need to be run manually.
