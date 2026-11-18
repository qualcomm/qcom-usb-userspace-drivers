# Qualcomm USB Drivers (User Space) — Release Notes

**Current Version:** 1.0.2.3
**Date:** 07/28/2026

This document covers important information concerning Qualcomm USB Drivers (User Space).

## Table of Contents

1. [Qualcomm USB Drivers (User Space) information](#1-qualcomm-usb-drivers-user-space-information)
2. [What's new in this release](#2-whats-new)

---

## 1. Qualcomm USB Drivers (User Space) information

Qualcomm USB Drivers (User Space) is built for Windows 10 / Windows 11 operating systems and is intended for use
with Qualcomm USB Host hardware and firmware supporting all Qualcomm VID/PIDs. Supported architectures include
x86, x64, and ARM64.

Starting with version 1.0.2.0, the installer was rewritten as a single self-extracting executable
(`qcom_usb_userspace_drivers_<arch>.exe`) that installs the pre-compiled filter driver, `qdinstall`/`qdclr` tools,
and libusb directly — replacing the previous "extract then run installer" flow.

---

## 2. What's new

### Current Release — Version 1.0.2.3

Installer updates:
- **QUD-1947:** Added a logging system to the Windows installer. Every install/uninstall run now writes a
  timestamped log to `C:\ProgramData\Qualcomm\QUD\`. (Tejas Sharma, [#26](../../pull/26))
- Fixed the installer calling `qdinstall` with `-x` during uninstall, which deleted the installer's own
  directory while it was still running. The installer now uses `qdinstall -u` instead. (Tejas Sharma, [#27](../../pull/27))

### Prior Release — Version 1.0.2.2

Installer / driver updates:
- Added missing device VID/PIDs (9139, 9148, and others) and fixed incorrect device mappings in the
  INF files. (Chenxi Han, [#23](../../pull/23))
- Replaced deprecated Win32 APIs used by `qdinstall`. (Chenxi Han, [#22](../../pull/22))
- Installer now copies the libusb DLL into `libusb\` without an architecture subfolder, matching the
  single-arch-per-installer packaging. (Chenxi Han, [#24](../../pull/24))

### Prior Release — Version 1.0.2.1

Installer updates:
- Added logic to package the libusb DLL with the userspace installer. (Tejas Sharma, [#16](../../pull/16))
- General installer fixes and updates for the 1.0.2.1 Windows release. (Chenxi Han, [#18](../../pull/18))
- Fixed a `qdinstall` race condition on re-install by splitting uninstall into separate `-u` (uninstall
  only) and `-x` (uninstall and remove install files) modes. (Chenxi Han, [#19](../../pull/19))
- Added license header and copyright info to all `.bat` and `.ps1` build scripts. (Chenxi Han, [#21](../../pull/21))

### Prior Release — Version 1.0.2.0

Installer updates:
- Added the scripts and C# project used to build a self-extracting installer on Windows. (Chenxi Han, [#10](../../pull/10))
- Updated scripts to install the pre-compiled filter driver. (Chenxi Han, [#11](../../pull/11))
- Additional build script and installer code optimization and cleanup. (Chenxi Han, [#12](../../pull/12))
- Added installation size calculation and fixed device enumeration issues. (Chenxi Han, [#13](../../pull/13))

### Prior Release — Version 1.00.1.6

Driver updates:
- Updated the installer to deploy the libusb dynamic library to a predefined location:
  `Program Files\<arch>\Qualcomm\QUD-Userspace\DriverPackage\libusb` based on system architecture.

### Prior Release — Version 1.00.1.5

Driver updates:
- Removed QPM QIK installer dependency.

### Prior Release — Version 1.00.1.4

Driver updates:
- Fixed uninstallation issues.

### Prior Release — Version 1.00.1.1

Driver updates:
- Fixed uninstallation issues.

### Prior Release — Version 1.00.1

Driver updates:
- MSFT Attested cat files are published.
- Error fixed for filter driver installation.

### Prior Release — Version 1.00.0

Driver updates:
- Added support for all the VID/PIDs.
