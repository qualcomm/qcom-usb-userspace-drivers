# Qualcomm USB Userspace Drivers
Qualcomm userspace drivers provides logical representations of Qualcomm chipset-enabled mobile devices over USB connection. The drivers support Windows & Linux environments.


## Key Features
  - Supports Windows and Linux platforms.
  - Supports X64/X86/ARM64 architectures.
  - Compatible with Qualcomm tools like QUTS, QXDM, QDL, and more.

## Repository Structure

```
/
├─ src/                   # Qualcomm USB userspace driver source root directory
│   ├── linux/            # Linux userspace driver source
│   └── windows/          # Windows userspace driver source
│         ├── build.bat   # Build script to generate catalog (.cat) files
│         ├── sign.bat    # Script to sign catalog (.cat) files
│         ├── install.bat # Batch installer for all driver packages
│         ├── installer/  # Native .EXE installer source (C, CMake)
│         └── *.inf       # Driver setup information files
├─ README.md              # This file
└─ ...                    # Other files and directories
```

## Build (Windows)

Driver catalog (`.cat`) files must be generated before installation. These files contain
cryptographic hashes that Windows uses to verify driver integrity during installation.

### Prerequisites
- [Windows Driver Kit (WDK)](https://learn.microsoft.com/en-us/windows-hardware/drivers/download-the-wdk) — provides `inf2cat.exe`
- [Windows SDK](https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/) — provides `signtool.exe` (required only for signing)
- A valid code signing certificate (required only for signing)

### Generate catalog files
```bash
src\windows\build.bat
```

### Sign catalog files
```bash
src\windows\sign.bat "Your Certificate Subject Name"
```

### Build the self-extracting .EXE installer (optional)
The installer is a single self-extracting EXE that embeds all INF + CAT files as a
ZIP payload appended to the binary. At runtime it extracts the payload to a temp
directory, installs every `.inf` via `pnputil`, then cleans up.

**Additional prerequisites:**
- [CMake](https://cmake.org/) and [Visual Studio](https://visualstudio.microsoft.com/) (or the MSVC Build Tools)
- [Python 3](https://www.python.org/) (for the packaging step)

> **Note:** The installer uses [miniz](https://github.com/richgel999/miniz) (MIT license)
> for ZIP extraction, which is vendored in `src/windows/installer/`.

```bash
REM 1. Generate .cat files (if not already done)
src\windows\build.bat

REM 2. Build the installer EXE and package driver files into it
src\windows\installer\package.bat
```
The output `QcomUsbDriverInstaller.exe` will be in `src\windows\installer\`.

## Install / Uninstall

#### Windows
- Installation

  - Right click the `.inf` file and select **Install**, or
  - Run `src\windows\install.bat` (batch script), or
  - Run `QcomUsbDriverInstaller.exe` (native installer, auto-elevates to admin)

- Uninstallation (Device Manager)
1. Open **Device Manager**.
2. Right click the target device and select **Uninstall device**.
3. Check **Attempt to remove the driver for this device**.
4. Click **Uninstall**.

- Uninstallation (Command Line)
1. Locate the **Published Name** of the installed driver package:
  ```bash
  pnputil /enum-drivers
  ```
2. Delete the driver from system
  ```bash
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