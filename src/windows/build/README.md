# Qualcomm USB Userspace Drivers — Windows Installer Build

This document describes how to build the Windows installer for the Qualcomm USB
Userspace Drivers package. A single top-level script handles everything: driver
binaries, per-architecture tool binaries, self-extracting installer EXEs, and
code signing.

---

## Prerequisites

| Requirement | Details |
|---|---|
| **OS** | Windows 10 or later (x64 host) |
| **Visual Studio** | 2019 or 2022 with the **Desktop development with C++** workload (includes MSBuild). Auto-detected via `vswhere.exe`. |
| **.NET Framework 4** | Required by `csc.exe` to compile the self-extracting installer. Ships with Windows; verify with `csc.exe /version`. |
| **Windows Driver Kit (WDK)** | Required to build the driver `.sys`/`.inf` files. |
| **PowerShell** | Version 5.0 or later (ships with Windows 10+). |
| **Code-signing server** *(optional)* | An EVSS (EV Signing Server) reachable at `localhost:3197` for signing. If unavailable, signing is skipped with a warning and the unsigned EXEs are still produced. |

---

## Repository Layout

```
src/windows/build/
├── build_installer.bat      ← Top-level entry point (run this)
├── build_drivers.bat        ← Builds driver .sys/.inf binaries + signs them
├── build_drivers.ps1        ← PowerShell implementation of the driver build
├── build_tools.ps1          ← Builds qdclr.exe and qdinstall.exe via MSBuild
├── build-installer.ps1      ← Packages payload.zip and compiles the C# installer EXE
├── sign.ps1                 ← EV / attestation code-signing helper
├── qdclr/                   ← DriverStore cleanup tool (C++ source)
├── qdinstall/               ← Driver lifecycle management tool (C++ source)
└── target/                  ← All build output lands here (created automatically)
```

---

## Build Steps

### 1. Open a Developer Command Prompt

Open a standard **Command Prompt** (or PowerShell). No special Developer
Command Prompt is required — MSBuild is located automatically via `vswhere.exe`.

### 2. Navigate to the build directory

```cmd
cd src\windows\build
```

### 3. Run the top-level build script

```cmd
build_installer.bat
```

That is the only command needed.

### 4. Collect the output

On success, three signed installer executables are written to `target\`:

```
target\
├── qcom_usb_userspace_drivers_x86.exe
├── qcom_usb_userspace_drivers_x64.exe
└── qcom_usb_userspace_drivers_arm64.exe
```

---

## What the Installer Does

### Install (default / `--install`)

1. Auto-elevates to Administrator via UAC.
2. Uninstalls any legacy packages (`qualcomm_userspace_driver`, `qud`, `qud.slt`, `qud.internal`) via `qpm-cli`.
3. Extracts the embedded `payload.zip` to `%ProgramFiles%\Qualcomm\Qualcomm USB Drivers`.
4. Runs `qdinstall.exe -i -p "<install path>"` which:
   - Removes stale DriverStore entries via `qdclr.exe`.
   - Installs all `.inf` drivers via `pnputil /add-driver *.inf /install /force`.
   - Triggers device tree re-enumeration.
   - Registers the package under **Add/Remove Programs** in the Windows registry.

### Uninstall (`--uninstall` or via Control Panel)

1. Auto-elevates to Administrator via UAC.
2. Reads the uninstall command from the registry.
3. Runs `qdinstall.exe -x` which removes DriverStore entries and the registry entry.
4. Deletes `%ProgramFiles%\Qualcomm\Qualcomm USB Drivers`.

### Other flags

| Flag | Description |
|---|---|
| `--version` / `-v` | Prints the package version (from `qcversion.h` at build time). |
| `--install` / `-i` | Explicit install (same as running with no arguments). |
| `--uninstall` / `-u` | Uninstall. |

---

## Versioning

The installer version is read at build time from:

```
src/windows/qcversion.h
```

```c
#define QCOM_USB_DRIVERS_PRODUCT_VERSION 1.0.2.0
```

Update this value before building to stamp a new version into the installer
assembly metadata and the `--version` output.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `[ERROR] MSBuild.exe could not be found.` | Visual Studio not installed or `vswhere.exe` missing. | Install Visual Studio 2019/2022 with the **Desktop development with C++** workload. |
| `[ERROR] csc.exe not found.` | .NET Framework 4 not present. | Install **.NET Framework 4** (or the Developer Pack). |
| `[ERROR] build_drivers.bat failed. Aborting.` | Driver build failed before the installer loop started. | Check WDK installation and review the driver build output above the error. |
| `[WARN] Signing failed for <arch>.` | EVSS signing server not reachable at `localhost:3197`. | The unsigned EXE is still available in `target\`. Configure the signing server or sign manually. |
| `[ERROR] Drivers directory not found: target\drivers` | Driver build did not produce output. | Ensure `build_drivers.bat` completes successfully before re-running. |
