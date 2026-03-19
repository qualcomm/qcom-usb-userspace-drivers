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
