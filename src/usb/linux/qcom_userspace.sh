#!/bin/bash

CUR_DIR="$(cd "$(dirname "$0")" && pwd)"
QCOM_DEST_USERSPACE=/opt/qcom/qcom_userspace
NEW_DEST_QUD_PATH=/opt/qcom/QUD
OLD_DEST_QUD_PATH=/opt/QTI/QUD
BUILD_DIR=build
NEW_QCOM_INSTALLER_FILE=qcom_drivers.sh
OLD_QCOM_INSTALLER_FILE=QcDevDriver.sh
QCOM_USB_MODULE_NAME=qcom_usb.ko
QCOM_USBNET_MODULE_NAME=qcom_usbnet.ko
QCOM_USB_DRIVER_PATH=/lib/modules/`uname -r`/kernel/drivers/usb/misc
QCOM_USBNET_DRIVER_PATH=/lib/modules/`uname -r`/kernel/drivers/net/usb
OLD_QCOM_DRIVER_PATH=/lib/modules/`uname -r`/kernel/drivers/net/usb
MODULE_BLACKLIST_PATH=/lib/modules/`uname -r`/kernel/drivers/usb/serial
MODULE_BLACKLIST_CONFIG=/etc/modprobe.d
OLD_QCOM_MODULE_INF_NAME=qtiDevInf.ko
OLD_QCOM_MODULE_QDSS_DIAG_NAME=QdssDiag.ko
OLD_QCOM_MODULE_RMNET_NAME=GobiNet.ko
QCOM_SYSTEMD_PATH=/etc/systemd/system
QCOM_QUDSERVICE=qcom-qud.service
QCOM_MODBIN_DIR=/sbin
QCOM_MAKE_DIR=/usr/bin
QCOM_LN_RM_MK_DIR=/bin
MODULE_BLACKLIST=/etc/modprobe.d
QCOM_MODBIN_DIR=/sbin
#QCOM_USERSPACE_SUPPORT_CONFIG_PATH=/etc/qcom_userspace.conf
QCOM_USERSPACE_SUPPORT_CONFIG_PATH=/etc/qcom_libusb.conf
QCOM_UDEV_PATH=/etc/udev/rules.d


if [  ! -d $QCOM_DEST_USERSPACE  ]; then
   echo -e ${RED}"Error: $QCOM_DEST_USERSPACE doesn't exist. Creating Now."${RESET}
   $QCOM_LN_RM_MK_DIR/mkdir -m 0755 -p $QCOM_DEST_USERSPACE
fi

if [ -d $QCOM_DEST_USERSPACE  ]; then
	$QCOM_LN_RM_MK_DIR/cp -rf $CUR_DIR/$NEW_QCOM_INSTALLER_FILE $QCOM_DEST_USERSPACE/
	$QCOM_LN_RM_MK_DIR/cp -rf $CUR_DIR/$OLD_QCOM_INSTALLER_FILE $QCOM_DEST_USERSPACE/
fi

if [ $# == 0 ]; then
	echo -e ----------------------------------
	echo -e "Usage: $0 options"
	echo -e "$0 <install | uninstall>"
	echo -e ----------------------------------
	exit 1
else
	if [ $1 == "install" ]; then

		$QCOM_LN_RM_MK_DIR/chmod +x $QCOM_DEST_USERSPACE/$NEW_QCOM_INSTALLER_FILE
		$QCOM_LN_RM_MK_DIR/chmod +x $QCOM_DEST_USERSPACE/$OLD_QCOM_INSTALLER_FILE

		if [[ -f $QCOM_USBNET_DRIVER_PATH/$QCOM_USBNET_MODULE_NAME ]] || [[ -f $QCOM_USB_DRIVER_PATH/$QCOM_USB_MODULE_NAME ]]; then
			#sudo pkill QUTS
			sudo $QCOM_LN_RM_MK_DIR/bash -c "$QCOM_DEST_USERSPACE/$NEW_QCOM_INSTALLER_FILE uninstall"
		fi

		if [[ -f $OLD_QCOM_DRIVER_PATH/$OLD_QCOM_MODULE_INF_NAME ]] || [[ -f $OLD_QCOM_DRIVER_PATH/$OLD_QCOM_MODULE_QDSS_DIAG_NAME ]] || [[ -f $OLD_QCOM_DRIVER_PATH/$OLD_QCOM_MODULE_RMNET_NAME ]]; then
			#sudo pkill QUTS
			sudo $QCOM_LN_RM_MK_DIR/bash -c "$QCOM_DEST_USERSPACE/$OLD_QCOM_INSTALLER_FILE uninstall"
		fi

		# QUDservice
		if [ -f $QCOM_SYSTEMD_PATH/$QCOM_QUDSERVICE ]; then
			sudo systemctl daemon-reload
			sudo systemctl stop $QCOM_QUDSERVICE
			sudo systemctl disable $QCOM_QUDSERVICE
			sudo $QCOM_LN_RM_MK_DIR/rm -rf $QCOM_SYSTEMD_PATH/$QCOM_QUDSERVICE
		elif [ ! -f $QCOM_SYSTEMD_PATH/$QCOM_QUDSERVICE ]; then
			echo "$QCOM_SYSTEMD_PATH/$QCOM_QUDSERVICE unit file Doesn't exist"
		else
			echo "Error: Failed to delete $QCOM_SYSTEMD_PATH/$QCOM_QUDSERVICE"
		fi

		# OLDQUDservice
		if [ -f $QCOM_SYSTEMD_PATH/QUDService.service ]; then
			sudo systemctl daemon-reload
			sudo systemctl stop QUDService
			sudo systemctl disable QUDService.service
			sudo $QCOM_LN_RM_MK_DIR/rm -rf $QCOM_SYSTEMD_PATH/QUDService.service
		elif [ ! -f $QCOM_SYSTEMD_PATH/QUDService.service ]; then
			echo "$QCOM_SYSTEMD_PATH/QUDService.service unit file Doesn't exist"
		else
			echo "Error: Failed to delete $QCOM_SYSTEMD_PATH/QUDService.service"
		fi

		#install libusb static library
		# if [ ! -f /usr/local/lib/libusb-1.0.a ]; then
		# 	cd $QCOM_DEST_USERSPACE
		# 	git clone https://github.com/libusb/libusb.git
		# 	cd $QCOM_DEST_USERSPACE/libusb
		# 	git checkout tags/v1.0.27 -b V1.0.27
		# 	sudo apt-get install autoconf libtool
		# 	./autogen.sh
		# 	make clean
		# 	./configure --enable-udev --enable-static CFLAGS="-fPIC"
		# 	make -j$(nproc)
		# 	sudo make install
		# fi

		#echo Changing Permission of blacklist file
		$QCOM_LN_RM_MK_DIR/chmod 777 $MODULE_BLACKLIST_CONFIG/blacklist.conf

		MOD_EXIST="`grep -nr  'blacklist qcserial' /etc/modprobe.d/blacklist.conf`"
		if [ "$MOD_EXIST" != "" ]; then
			sed -i '/qcserial/d' $MODULE_BLACKLIST_CONFIG/blacklist.conf
		fi

		echo -e "blacklist qcserial" >> /etc/modprobe.d/blacklist.conf
		echo -e "install qcserial /bin/false" >> /etc/modprobe.d/blacklist.conf
		echo -e "blacklisted qcserial module"

		MODLOADED="`/sbin/lsmod | grep qcserial`"
		if [ "$MODLOADED" != "" ]; then
			echo -e "qcserial is found. Unloaded qcserial module"
			$QCOM_MODBIN_DIR/rmmod qcserial.ko
			MODLOADED="`/sbin/lsmod | grep qcserial`"
			if [ "$MODLOADED" != "" ]; then
			echo -e ${RED}"Failed to unload qcserial.ko. try manually sudo rmmod ModuleName"${RESET}
			fi
		fi

		if [ -f $MODULE_BLACKLIST_PATH/qcserial.ko ]; then
			echo -e "qcserial is found. renamed to qcserial_dup"
			mv /lib/modules/`uname -r`/kernel/drivers/usb/serial/qcserial.ko /lib/modules/`uname -r`/kernel/drivers/usb/serial/qcserial_dup
		fi

		depmod

		echo SUBSYSTEM==\"usb\", ATTR{idVendor}==\"05c6\", MODE=\"0666\", GROUP=\"plugdev\" >> ./99-qcom-userspace.rules

		$QCOM_LN_RM_MK_DIR/chmod 644 ./99-qcom-userspace.rules
		$QCOM_LN_RM_MK_DIR/cp -rf ./99-qcom-userspace.rules $QCOM_UDEV_PATH
		echo -e "Generated QCOM udev rules"
		$QCOM_LN_RM_MK_DIR/rm -rf ./99-qcom-userspace.rules

		# Informs udev deamon to reload the newly added device rule and re-trigger service
		sudo udevadm control --reload-rules
		sudo udevadm trigger

		if [ ! -f $QCOM_UDEV_PATH/99-qcom-userspace.rules ]; then
			echo -e "Error: Failed to generate $QCOM_UDEV_PATH/99-qcom-userspace.rules"
			exit 1
		fi
		
		echo "QCOM_USERSPACE_SUPPORT=1" | sudo tee $QCOM_USERSPACE_SUPPORT_CONFIG_PATH
		echo "QCOM_LIBUSB_SUPPORT=1" >> $QCOM_USERSPACE_SUPPORT_CONFIG_PATH
		echo -e "Enable qcom-userspace communication"

	elif [ $1 == "uninstall" ]; then

		MODLOADED="`/sbin/lsmod | grep qcserial`"
		if [ "$MODLOADED" != "" ]; then
			echo -e "qcserial module is already loaded. nothing to do"
		fi

		if [ -f $MODULE_BLACKLIST_PATH/qcserial_dup* ]; then
			echo -e "qcserial_dup is found. restoring to qcserial"
			mv /lib/modules/`uname -r`/kernel/drivers/usb/serial/qcserial_dup* /lib/modules/`uname -r`/kernel/drivers/usb/serial/qcserial.ko
			#$QCOM_MODBIN_DIR/insmod /lib/modules/`uname -r`/kernel/drivers/usb/serial/qcserial.ko

			MODLOADED="`/sbin/lsmod | grep qcserial`"
			if [ "$MODLOADED" != "" ]; then
				echo -e "Successfully loaded qcserial module."
			fi
		fi

		if [ "`grep -nr 'Qualcomm clients' /etc/modprobe.d/blacklist.conf`" != "" ]; then
			sed -i '/# Blacklist these module so that Qualcomm clients use only/d' /etc/modprobe.d/blacklist.conf
			sed -i '/# qcom_usbnet, qcom_usb driver/d' /etc/modprobe.d/blacklist.conf
		fi

		MOD_EXIST="`grep -nr  'blacklist qcserial' /etc/modprobe.d/blacklist.conf`"
		if [ "$MOD_EXIST" != "" ]; then
			sed -i '/qcserial/d' $MODULE_BLACKLIST_CONFIG/blacklist.conf
			echo -e "Successfully removed qcserial from $MODULE_BLACKLIST_CONFIG/blacklist.conf"
		fi

		#change to permission to default mode
		$QCOM_LN_RM_MK_DIR/chmod 644 $MODULE_BLACKLIST_CONFIG/blacklist.conf

		depmod

		if [ -f $QCOM_UDEV_PATH/99-qcom-userspace.rules ]; then
			$QCOM_LN_RM_MK_DIR/rm -rf $QCOM_UDEV_PATH/99-qcom-userspace.rules
			if [ ! -f $QCOM_UDEV_PATH/99-qcom-userspace.rules ]; then
				echo -e "Successfully removed $QCOM_UDEV_PATH/99-qcom-userspace.rules"
			else
				echo -e "Failed to remove $QCOM_UDEV_PATH/99-qcom-userspace.rules"
			fi
		else
			echo -e "$QCOM_UDEV_PATH/99-qcom-userspace.rules does not exist, nothing to remove"
		fi

		# Informs udev deamon to reload rules database and re-trigger service
		sudo udevadm control --reload-rules
		sudo udevadm trigger

		$QCOM_LN_RM_MK_DIR/rm -f $QCOM_USERSPACE_SUPPORT_CONFIG_PATH
		echo -e "Disable qcom-userspace config file"
		$QCOM_LN_RM_MK_DIR/rm -f /dev/QCOM_USERSPACE*
		$QCOM_LN_RM_MK_DIR/rm -f /dev/QCOM_LIBUSB*

		echo -e "Uninstallation completed successfully."
	else
		echo -e ----------------------------------
		echo -e "you have entered invalid option: $1"
		echo -e "Usage: $0 options"
		echo -e "$0 <install | uninstall>"
		echo -e ----------------------------------
		exit 1
	fi
fi

exit 0
