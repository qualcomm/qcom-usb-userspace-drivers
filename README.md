# Qualcomm USB Userspace Drivers
Qualcomm userspace drivers provides logical representations of Qualcomm chipset-enabled mobile devices over USB connection. The drivers support Windows & Linux environments.


## Key Features
  - Supports Windows and Linux platforms.
  - Supports X64/X86/ARM64 architectures.
  - Compatible with Qualcomm tools like QUTS, QXDM, QDL, and more.

## Known Limitations

### No QMI Support
This userspace driver solution does **not** include support for the Qualcomm Messaging Interface (QMI) protocol. QMI is used to communicate with Qualcomm modem subsystems for functions such as data connectivity, voice, SMS, and network management. Applications or tools that rely on QMI-based communication are not supported by this driver.

Users requiring QMI functionality should use the appropriate kernel-mode drivers or a dedicated QMI userspace stack operating over those kernel interfaces.

### libusb Conflicts on Composite Devices When ADB Is Active

The Linux userspace driver uses [libusb](https://libusb.info/) to communicate directly with the USB device. Qualcomm devices typically enumerate as **USB composite devices**, exposing multiple interfaces simultaneously (e.g., ADB, Diag, modem, DPL). When the Android Debug Bridge (ADB) daemon is active and has claimed its interface on the composite device, libusb operations from this driver may encounter the following issues:

- **Interface claim failures** — libusb may fail to claim a required interface with `LIBUSB_ERROR_ACCESS` or `LIBUSB_ERROR_BUSY` if the ADB daemon or another process already holds it.
- **Unreliable I/O** — Even when interface claiming succeeds, concurrent access by ADB and libusb on the same composite device can cause dropped transfers, timeouts, or corrupted data.
- **Device re-enumeration** — In some cases, the conflict may cause the USB device to disconnect and re-enumerate, interrupting both ADB and the userspace driver session.

**Workaround:** Disable ADB on the device (or stop the ADB daemon on the host with `adb kill-server`) before using this userspace driver, to avoid interface contention on the composite device.


## Repository Structure

```
/
├─ src/                   # Qualcomm USB userspace driver source root directory
│   ├── linux/            # Linux userspace driver source
│   └── windows/          # Windows userspace driver source
│         ├── filter/     # Qualcomm USB composite device driver binaries
│         └── ...         # Signed driver setup information (INF) and catalog files
├─ README.md              # This file
└─ ...                    # Other files and directories
```

## Install / Uninstall

#### Windows
- Installation

  Right click the `.inf` file in output folder and select **Install**.
  Or install all drivers by executing `src\usb\windows\install.bat`

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
  Option 1. Directly using scripts for installation/uninstallation.
  Navigate to folder `src/linux/build`

- Installation
```bash
./qcom_userspace.sh install
```
- Uninstallation
```bash
./qcom_userspace.sh uninstall
```

  Option 2. Create debian package using pack_deb bash script.
  Navigate to folder `src/linux/`

```bash
- sudo chmod +x pack_deb
- ./pack_deb zip
```
  unzip and follow the instructions in the README.md inside the zip file.

## Build Instructions

### Prerequisites
- CMake 3.10 or higher
- GCC 7 or higher (Linux)
- Visual Studio 2019 or higher (Windows)

### Building

#### Linux
1. Navigate to `src/linux/build`
2. Run `cmake ..`
3. Run `make`

#### Windows
1. Navigate to `src/windows`
2. Open `qcom-usb-userspace.sln` in Visual Studio
3. Build the solution

## Usage

The drivers are automatically loaded when a compatible Qualcomm device is
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
