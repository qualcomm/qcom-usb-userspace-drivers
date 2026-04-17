## Instructions

# Install the .deb package:
unzip qualcomm-userspace-driver_x.xx.x.x_linux-anycpu.zip
sudo dpkg -i qualcomm-userspace-driver_x.xx.x.x_linux-anycpu.deb

# Uninstall the .deb package:
sudo dpkg -P qualcomm-userspace-driver
# or
sudo apt purge qualcomm-userspace-driver

# Confirm the package is removed:
dpkg -I | grep qualcomm-userspace-driver


## Limitation
  - Currently, driver only supports communication with one device one interface at a time, limiting multi-device usage.
  - RMNET/QMI/MBN operation is not supported.
