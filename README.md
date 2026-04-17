# Qualcomm USB Userspace Drivers
Qualcomm userspace drivers provides logical representations of Qualcomm chipset-enabled mobile devices over USB connection. The drivers support Windows & Linux environments.


## Key Features
  - Supports Windows and Linux platforms.
  - Supports X64/X86/ARM64 architectures.
  - Compatible with Qualcomm tools like QUTS, QXDM, QDL, and more.

## Repository Structure

```
/
├─ src/                        # Qualcomm USB userspace driver source root directory
│   ├── linux/                 # Linux userspace driver source
│   └── windows/               # Windows userspace driver source
│         ├── installer/       # Self-extracting installer (build scripts, C source)
│         └── ...              # Signed driver setup information (INF) and catalog files
├─ README.md                   # This file
└─ ...                         # Other files and directories
```

## Install / Uninstall

#### Windows — Self-Extracting Installer

The recommended way to install/manage drivers on Windows is the self-extracting
installer EXE produced by `src\windows\installer\package.bat`.

| Command | Description |
|---|---|
| `qcom-usb-userspace-drivers.exe` | Install drivers (auto-upgrades if an older version is found) |
| `qcom-usb-userspace-drivers.exe /query` | Query installed packages and detect conflicting drivers |
| `qcom-usb-userspace-drivers.exe /force` | Force install (bypass version check — reinstall or downgrade) |
| `qcom-usb-userspace-drivers.exe /version` | Print installer version and exit |
| `qcom-usb-userspace-drivers.exe /help` | Print usage help |

> **Note:** The installer requires Administrator privileges and will prompt for
> elevation automatically.

The installer records the installed version, INF list, and install date in the
registry at `HKLM\SOFTWARE\Qualcomm\QcomUsbDrivers`. Before installing, the
installer automatically detects and removes **all conflicting driver packages**:

| Conflict type | Detection method | Removal method |
|---|---|---|
| Previous userspace driver installation | Registry INF list at `HKLM\SOFTWARE\Qualcomm\QcomUsbDrivers` | `pnputil /delete-driver` for each recorded INF |
| Kernel-mode driver packages (`qcfilter`, `qcwwan`, `qdbusb`, `qcwdfmdm`, `qcwdfser`) | `pnputil /enum-drivers` matching original INF name | `pnputil /delete-driver /uninstall /force` |
| Legacy QPM-managed packages (`QUD`, `QUD.internal`, `Qualcomm_Userspace_Driver`) | `qpm-cli` availability on PATH | `qpm-cli --uninstall <package>` |

All conflict removal is non-fatal — if a conflicting package is not found or
removal fails, installation proceeds normally.

**Building the installer:**
```bat
cd src\windows\installer
package.bat
```
This produces `qcom-usb-userspace-drivers_<version>.exe` in the current directory.

#### Windows — Manual Installation

- **Install:** Right-click the `.inf` file and select **Install**.

- **Uninstall (Device Manager):**
  1. Open **Device Manager**.
  2. Right-click the target device and select **Uninstall device**.
  3. Check **Attempt to remove the driver for this device**.
  4. Click **Uninstall**.

- **Uninstall (Command Line):**
  1. Locate the **Published Name** of the installed driver package:
     ```bat
     pnputil /enum-drivers
     ```
  2. Delete the driver from the system:
     ```bat
     pnputil /delete-driver oemxx.inf /uninstall /force
     ```
#### Linux command:
  Navigate to folder `src/linux`

- Installation
```bash
./qcom_userspace.sh install
```
- Uninstallation
```bash
./qcom_userspace.sh uninstall
```

## Contributing

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/my-feature`).
3. Make your changes and ensure they compile on all supported platforms.
4. Submit a pull request with a clear description of the changes.

Please follow the existing coding style and run the appropriate static analysis tools before submitting.

## Bug & Vulnerability reporting

Please review the [security](./SECURITY.md) before reporting vulnerabilities with the project

## Contributor's License Agreement

Please review the Qualcomm product [license](./LICENSE.txt), [code of conduct](./CODE-OF-CONDUCT.md) & terms
and conditions before contributing.

## Contact

For questions, bug reports, or feature requests, please open an issue on GitHub or contact the maintainers
