#!/bin/bash

DEST_QCOM_PATH=/opt/qcom/
DEST_QUD_PATH=/opt/qcom/QUD
DEST_QCOM_NET_PATH=/opt/qcom/QUD/qcom_net
DEST_QCOM_USB_PATH=/opt/qcom/QUD/qcom_usb
DEST_SIGN_PATH=/opt/qcom/QUD/sign
OLD_DEST_SIGN_PATH=/opt/QTI/sign
QCOM_MODBIN_DIR=/sbin
QCOM_MAKE_DIR=/usr/bin
QCOM_USB_MODULE_NAME=qcom_usb.ko
QCOM_USBNET_MODULE_NAME=qcom_usbnet.ko
QCOM_UDEV_PATH=/etc/udev/rules.d
MODULE_BLACKLIST_PATH=/lib/modules/`uname -r`/kernel/drivers/usb/serial
QCOM_USBNET_AND_QMI_WWAN=/lib/modules/`uname -r`/kernel/drivers/net/usb
QCOM_NET_DEPENDENCY_PATH=/lib/modules/`uname -r`/kernel/drivers/net
QCOM_USB_KERNEL_PATH=/lib/modules/`uname -r`/kernel/drivers/usb/misc
QCOM_LN_RM_MK_DIR=/bin
QCOM_DRIVER_DEBUG_ENABLE=$2
MODULE_BLACKLIST_CONFIG=/etc/modprobe.d
OS_RELEASE="`cat /etc/os-release | grep PRETTY_NAME`"
OSName=`echo $OS_RELEASE | awk -F= '{printf $2}'`
KERNEL_VERSION=`uname -r`
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

#check and install mokutil package
if [ ! -f "$QCOM_MAKE_DIR/mokutil" ]; then
   echo -e ${RED}"Error: mokutil not found, installing..\n"${RESET}
fi

if [ ! -f "$QCOM_MAKE_DIR/keyctl" ]; then
   echo -e ${RED}"Error: keyutils not found, installing..\n"${RESET}
fi

if [[ ! -f "$QCOM_MAKE_DIR/mokutil" ]] || [[ ! -f "$QCOM_MAKE_DIR/keyctl" ]]; then
   if [[ $OSName =~ "Red Hat Enterprise Linux" ]]; then
      sudo dnf install -y mokutil
      sudo dnf install -y keyutils
   fi

   if [[ $OSName =~ "Ubuntu" ]]; then
      sudo apt-get install -y mokutil
      sudo apt-get install -y keyutils
   fi
fi

if [[ $OSName =~ "Fedora Linux" ]]; then
   sudo dnf install -y make automake gcc gcc-c++ kernel-devel
fi

QCOM_SECURE_BOOT_CHECK=`mokutil --sb-state`

if [[ $QCOM_SECURE_BOOT_CHECK = "SecureBoot enabled" ]]; then
   QCOM_PUBLIC_KEY_VERIFY=`mokutil --test-key $DEST_SIGN_PATH/Signkey_pub.der`
fi

if [  ! -d $DEST_QCOM_PATH  ]; then
   echo -e ${RED}"Error: $DEST_QCOM_PATH doesn't exist. Creating Now."${RESET}
   $QCOM_LN_RM_MK_DIR/mkdir -m 0755 -p $DEST_QCOM_PATH
fi

if [  ! -d $DEST_QUD_PATH  ]; then
   echo -e ${RED}"Error: $DEST_QUD_PATH doesn't exist. Creating Now."${RESET}
   $QCOM_LN_RM_MK_DIR/mkdir -m 0755 -p $DEST_QUD_PATH
fi

if [ $# == 0 ]; then
	echo -e ${RED}"Usage:"${RESET}
   	echo -e ${RED}"driver_load.sh OPTION1 OPTION2"${RESET}
	echo -e ${RED}"OPTION 1"${RESET}
	echo -e ${RED}"driver_load.sh <install | uninstall>"${RESET}
	echo -e ${RED}"OPTION 2"${RESET}
	echo -e ${RED}"driver_load.sh <install | uninstall> <enable debug messages for driver - choose option qcom_usb | qcom_usbnet | all>"${RESET}
	echo -e ${RED}"example: ./driver_load.sh install qcom_usb"${RESET}
   exit 1
else
   if [ $1 == "uninstall" ]; then
	echo -e "Operating System: $OSName"
	echo -e "Kernel Version: "\""`uname -r`"\"""

      if [ -d $DEST_QCOM_USB_PATH ]; then
         $QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_USB_PATH
         if [ ! -d $DEST_QCOM_USB_PATH ]; then
            echo -e "Successfully removed $DEST_QCOM_USB_PATH"
         else
            echo -e ${RED}"Failed to remove $DEST_QCOM_USB_PATH"${RESET}
         fi
      else
         echo -e "$DEST_QCOM_USB_PATH does not exist, nothing to remove"
      fi
      if [ -d $DEST_QCOM_NET_PATH ]; then
         $QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_NET_PATH
         if [ ! -d $DEST_QCOM_NET_PATH ]; then
            echo -e "Successfully removed $DEST_QCOM_NET_PATH"
         else
            echo -e ${RED}"Failed to remove $DEST_QCOM_NET_PATH"${RESET}
         fi
      else
         echo -e "$DEST_QCOM_NET_PATH does not exist, nothing to remove"
      fi

      if [ -f $QCOM_UDEV_PATH/qcom-usb-devices.rules ]; then
         rm -r $QCOM_UDEV_PATH/qcom-usb-devices.rules
         if [ ! -f $QCOM_UDEV_PATH/qcom-usb-devices.rules ]; then
            echo -e "Successfully removed $QCOM_UDEV_PATH/qcom-usb-devices.rules"
         else
            echo -e ${RED}"Failed to remove $QCOM_UDEV_PATH/qcom-usb-devices.rules"${RESET}
         fi
      else
         echo -e "$QCOM_UDEV_PATH/qcom-usb-devices.rules does not exist, nothing to remove"
      fi
      if [ -f $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules ]; then
         sed -i '/usb/d' $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules
         if [ ! -s $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules ]; then
            echo -e "Removed qcom_usbnet rule from $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules"
            rm -rf $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules
            if [ ! -f $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules ]; then
               echo -e "File was empty. Removed $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules successfully"
            else
               echo -e "File is empty but Failed to remove $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules"
            fi
         else
               echo -e "Pre-Existing data $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules, so not removing it."
         fi
      else
         echo -e "$QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules does not exist, nothing to remove"
      fi

      # Informs udev deamon to reload the newly added device rule and re-trigger service
      sudo udevadm control --reload-rules
      sudo udevadm trigger

      if [ "`lsmod | grep qcom_usbnet`" ]; then
         ( $QCOM_MODBIN_DIR/rmmod $QCOM_USBNET_MODULE_NAME && echo -e "$QCOM_USBNET_MODULE_NAME removed successfully" ) || { echo -e "$QCOM_USBNET_MODULE_NAME in use"; echo -e ${RED}"Note: ${CYAN} Close all applications that make use of the driver, including QUTS clients."; echo -e ${RED}"ps -aux | grep QUTS, sudo kill -9 <PID> OR sudo pkill QUTS$"; echo -e ${GREEN}"Try $1ation again!"${RESET}; exit 1; }
      else
         echo -e "Module $QCOM_USBNET_MODULE_NAME is not currently loaded"
      fi
      if [ "`lsmod | grep qcom_usb`" ]; then
         ($QCOM_MODBIN_DIR/rmmod $QCOM_USB_MODULE_NAME && echo -e "$QCOM_USB_MODULE_NAME removed successfully") || { echo -e "$QCOM_USB_MODULE_NAME in use"; echo -e ${RED}"Note: ${CYAN} Close all applications that make use of the driver, including QUTS clients."; echo -e ${RED}"ps -aux | grep QUTS, sudo kill -9 <PID> OR sudo pkill QUTS$"; echo -e ${GREEN}"Try $1ation again!"${RESET}; exit 1; }
      else
         echo -e "Module $QCOM_USB_MODULE_NAME is not currently loaded"
      fi

      MODLOADED="`/sbin/lsmod | grep usb_wwan`"
      if [ "$MODLOADED" != "" ]; then
         echo -e "usb_wwan module is already loaded. nothing to do"
      fi
      if [  -f $MODULE_BLACKLIST_PATH/usb_wwan_dup* ]; then
         echo -e "usb_wwan_dup is found. restoring to usb_wwan"
         mv /lib/modules/`uname -r`/kernel/drivers/usb/serial/usb_wwan_dup* /lib/modules/`uname -r`/kernel/drivers/usb/serial/usb_wwan.ko
         #$QCOM_MODBIN_DIR/insmod /lib/modules/`uname -r`/kernel/drivers/usb/serial/usb_wwan.ko

         MODLOADED="`/sbin/lsmod | grep usb_wwan`"
         if [ "$MODLOADED" != "" ]; then
            echo -e "Successfully loaded usb_wwan module."
         fi
      fi

      MODLOADED="`/sbin/lsmod | grep qcserial`"
      if [ "$MODLOADED" != "" ]; then
         echo -e "qcserial module is already loaded. nothing to do"
      fi
      if [  -f $MODULE_BLACKLIST_PATH/qcserial_dup* ]; then
         echo -e "qcserial_dup is found. restoring to qcserial"
         mv /lib/modules/`uname -r`/kernel/drivers/usb/serial/qcserial_dup* /lib/modules/`uname -r`/kernel/drivers/usb/serial/qcserial.ko
         #$QCOM_MODBIN_DIR/insmod /lib/modules/`uname -r`/kernel/drivers/usb/serial/qcserial.ko

         MODLOADED="`/sbin/lsmod | grep qcserial`"
         if [ "$MODLOADED" != "" ]; then
            echo -e "Successfully loaded qcserial module."
         fi
      fi

      MODLOADED="`/sbin/lsmod | grep option`"
      if [ "$MODLOADED" != "" ]; then
         echo -e "option module is already loaded. nothing to do"
      fi
      if [  -f $MODULE_BLACKLIST_PATH/option_dup* ]; then
         echo -e "option_dup is found. restoring to option"
         mv /lib/modules/`uname -r`/kernel/drivers/usb/serial/option_dup* /lib/modules/`uname -r`/kernel/drivers/usb/serial/option.ko
         #$QCOM_MODBIN_DIR/insmod /lib/modules/`uname -r`/kernel/drivers/usb/serial/option.ko

         MODLOADED="`/sbin/lsmod | grep option`"
         if [ "$MODLOADED" != "" ]; then
            echo -e "Successfully loaded option module."
         fi
      fi

      MODLOADED="`/sbin/lsmod | grep qmi_wwan`"
      if [ "$MODLOADED" != "" ]; then
         echo -e "qmi_wwan module is already loaded. nothing to do"
      fi
      if [  -f $QCOM_USBNET_AND_QMI_WWAN/qmi_wwan_dup* ]; then
         echo -e "qmi_wwan_dup is found. restoring to qmi_wwan"
         mv /lib/modules/`uname -r`/kernel/drivers/usb/class/cdc-wdm_dup* /lib/modules/`uname -r`/kernel/drivers/usb/class/cdc-wdm.ko
         mv /lib/modules/`uname -r`/kernel/drivers/net/usb/qmi_wwan_dup* /lib/modules/`uname -r`/kernel/drivers/net/usb/qmi_wwan.ko
         #$QCOM_MODBIN_DIR/insmod /lib/modules/`uname -r`/kernel/drivers/usb/class/cdc-wdm.ko
         #$QCOM_MODBIN_DIR/insmod /lib/modules/`uname -r`/kernel/drivers/net/usb/qmi_wwan.ko

         MODLOADED="`/sbin/lsmod | grep qmi_wwan`"
         if [ "$MODLOADED" != "" ]; then
            echo -e "Successfully loaded qmi_wwan module."
         fi
      fi

      if  [[ $OSName =~ "Ubuntu 24.04" ]]; then
         if [ -f $QCOM_NET_DEPENDENCY_PATH/mii.ko ]; then
            $QCOM_LN_RM_MK_DIR/rm -rf $QCOM_NET_DEPENDENCY_PATH/mii.ko
         fi
         if [ -f $QCOM_USBNET_AND_QMI_WWAN/usbnet.ko ]; then
            $QCOM_LN_RM_MK_DIR/rm -rf $QCOM_USBNET_AND_QMI_WWAN/usbnet.ko
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

      MOD_EXIST="`grep -nr  'blacklist qmi_wwan' /etc/modprobe.d/blacklist.conf`"
      if [ "$MOD_EXIST" != "" ]; then
         sed -i '/qmi_wwan/d' $MODULE_BLACKLIST_CONFIG/blacklist.conf
         echo -e "Successfully removed qmi_wwan from $MODULE_BLACKLIST_CONFIG/blacklist.conf"
      fi

      MOD_EXIST="`grep -nr  'blacklist option' /etc/modprobe.d/blacklist.conf`"
      if [ "$MOD_EXIST" != "" ]; then
         sed -i '/option/d' $MODULE_BLACKLIST_CONFIG/blacklist.conf
         echo -e "Successfully removed option from $MODULE_BLACKLIST_CONFIG/blacklist.conf"
      fi

      MOD_EXIST="`grep -nr  'blacklist usb_wwan' /etc/modprobe.d/blacklist.conf`"
      if [ "$MOD_EXIST" != "" ]; then
         sed -i '/usb_wwan/d' $MODULE_BLACKLIST_CONFIG/blacklist.conf
         echo -e "Successfully removed usb_wwan from $MODULE_BLACKLIST_CONFIG/blacklist.conf"
      fi

      #change to permission to default mode
      $QCOM_LN_RM_MK_DIR/chmod 644 $MODULE_BLACKLIST_CONFIG/blacklist.conf

      echo -e "Removing modules for /etc/modules."
      MODUPDATE="`grep -r qcom_usb /etc/modules`"
      if [ "$MODUPDATE" == "qcom_usb" ]; then
	  sed -i '/qcom_usb/d' /etc/modules
      fi
      MODUPDATE="`grep -r qcom_usbnet /etc/modules`"
      if [ "$MODUPDATE" == "qcom_usbnet" ]; then
	  sed -i '/qcom_usbnet/d' /etc/modules
      fi
      if [[ $OSName != *"Red Hat Enterprise Linux"* ]]; then
      	MODUPDATE="`grep -nr  'iface usb0 inet static' /etc/network/interfaces`"
      	if [ "$MODUPDATE" != "" ]; then
        	 sed -i '/iface usb0 inet static/d' /etc/network/interfaces
      	fi
      fi

      echo -e "Removing modules from $QCOM_USB_KERNEL_PATH"
      if [ -f $QCOM_USB_KERNEL_PATH/$QCOM_USB_MODULE_NAME ]; then
         rm -rf $QCOM_USB_KERNEL_PATH/$QCOM_USB_MODULE_NAME
      fi
      echo -e "Removing modules from $QCOM_USBNET_AND_QMI_WWAN"
      if [ -f $QCOM_USBNET_AND_QMI_WWAN/$QCOM_USBNET_MODULE_NAME ]; then
         rm -rf $QCOM_USBNET_AND_QMI_WWAN/$QCOM_USBNET_MODULE_NAME
      fi
	   # update modules.dep and modules.alias
      depmod

	   echo -e "Uninstallation completed successfully."
      exit 0
   else
      if [ $1 != "install" ]; then
         	echo -e ${RED}"Usage: OPTION1 mandatory"${RESET}
            echo -e ${RED}"./driver_load.sh OPTION1 OPTION2"${RESET}
	         echo -e ${RED}"OPTION 1: Only install|uninstall driver"${RESET}
	         echo -e ${RED}"./driver_load.sh <install | uninstall>"${RESET}
	         echo -e ${RED}"OPTION 2: install driver with debug messages enabled"${RESET}
	         echo -e ${RED}"driver_load.sh <install | uninstall> <enable debug messages for driver - choose option qcom_usb | qcom_usbnet | all>"${RESET}
            echo -e ${RED}"example: ./driver_load.sh install qcom_usb"${RESET}
         exit 1
      fi
   fi
fi

######## Installation ###########

if [[ $OSName =~ "Ubuntu" ]]; then
   sudo apt-get update
   sudo apt-get install -y build-essential
   sudo apt-get install -y gawk
   sudo apt-get install -y python3-tk
fi

IFS=. read -r major_ver minor_ver patch_ver <<< "$KERNEL_VERSION"
if [[ $OSName =~ "Ubuntu 22." ]] && (( "$major_ver" >= 6 && "$minor_ver" >= 5 )); then
   echo -e "Installing gcc 12 version ..."
   sudo apt install -y gcc-12 g++-12
fi

echo -e ${CYAN}"======================================================================================="
echo -e "======================================================================================="${RESET}
echo -e " "

echo -e "Operating System:${RED} $OSName"${RESET}
echo -e "Kernel Version: ${RED}"\"$KERNEL_VERSION\"""${RESET}

if [ -f ./version.h ]; then
   VERSION="`grep -r '#define DRIVER_VERSION' version.h`"
   DRIVER_VERSION=`echo $VERSION | awk '{printf $3}'`
   echo -e "Driver Version: $DRIVER_VERSION"
fi

echo -e "Installing at the following paths:"
echo $DEST_QCOM_USB_PATH
echo $DEST_QCOM_NET_PATH

$QCOM_LN_RM_MK_DIR/mkdir -p -m 0655 $DEST_QCOM_USB_PATH
if [  ! -d $DEST_QCOM_USB_PATH  ]; then
   echo -e ${RED}"Error: Failed to create installation path, please run installer under root."${RESET}
   exit 1
fi

# Important: Do not delete or recreate the "sign" folder.
# The sign files will be automatically generated whenever the Signpub key is not enrolled.
$QCOM_LN_RM_MK_DIR/mkdir -m 0777 -p $DEST_SIGN_PATH
if [ ! -d $DEST_SIGN_PATH ]; then
   echo -e ${RED}"Error: Failed to create installation path, please run installer under root."${RESET}
   exit 1
fi

$QCOM_LN_RM_MK_DIR/cp -rf ./qcom_usb/qcom_usb.c $DEST_QCOM_USB_PATH/
if [ ! -f $DEST_QCOM_USB_PATH/qcom_usb.c ]; then
   echo -e ${RED}"Error: Failed to copy 'qcom_usb/qcom_usb.c' to installation path, installation abort."${RESET}
   $QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_USB_PATH
   exit 1
fi

$QCOM_LN_RM_MK_DIR/cp -rf ./qcom_usb/Makefile $DEST_QCOM_USB_PATH/
if [ ! -f $DEST_QCOM_USB_PATH/Makefile ]; then
   echo -e ${RED}"Error: Failed to copy 'qcom_usb/Makefile' to installation path, installation abort."${RESET}
   $QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_USB_PATH
   exit 1
fi

$QCOM_LN_RM_MK_DIR/cp -rf ./Makefile $DEST_QUD_PATH/
if [ ! -f $DEST_QUD_PATH/Makefile ]; then
   echo -e ${RED}"Error: Failed to copy 'QUD/Makefile' to installation path, installation abort."${RESET}
   exit 1
fi

$QCOM_LN_RM_MK_DIR/cp -rf ./README.md $DEST_QUD_PATH/
if [ ! -f $DEST_QUD_PATH/README.md ]; then
   echo -e ${RED}"Error: Failed to copy 'QUD/README.md' to installation path, installation abort."${RESET}
   exit 1
fi

$QCOM_LN_RM_MK_DIR/mkdir -p -m 0655 $DEST_QCOM_NET_PATH
if [  ! -d $DEST_QCOM_NET_PATH  ]; then
   echo -e ${RED}"Error: Failed to create installation path, please run installer under root."${RESET}
   exit 1
fi

$QCOM_LN_RM_MK_DIR/cp -rf ./qcom_net/ipassignment.sh $DEST_QCOM_NET_PATH
if [ ! -f $DEST_QCOM_NET_PATH/ipassignment.sh ]; then
   echo -e ${RED}"Error: Failed to copy ipassignment.shto installation path, installation abort."${RESET}
   $QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_NET_PATH
   exit 1
fi

$QCOM_LN_RM_MK_DIR/chmod 755 $DEST_QCOM_NET_PATH/ipassignment.sh

$QCOM_LN_RM_MK_DIR/cp -rf ./qcom_net/qcom_net.c $DEST_QCOM_NET_PATH
if [ ! -f $DEST_QCOM_NET_PATH/qcom_net.c ]; then
   echo -e ${RED}"Error: Failed to copy qcom_net.c to installation path, installation abort."${RESET}
   $QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_NET_PATH
   exit 1
fi

$QCOM_LN_RM_MK_DIR/cp -rf ./qcom_net/qmidevice.c $DEST_QCOM_NET_PATH
if [ ! -f $DEST_QCOM_NET_PATH/qmidevice.c ]; then
   echo -e ${RED}"Error: Failed to copy qmidevice.c to installation path, installation abort."${RESET}
   $QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_NET_PATH
   exit 1
fi

$QCOM_LN_RM_MK_DIR/cp -rf ./qcom_net/qmidevice.h $DEST_QCOM_NET_PATH
if [ ! -f $DEST_QCOM_NET_PATH/qmidevice.h ]; then
   echo -e ${RED}"Error: Failed to copy qmidevice.h to installation path, installation abort."${RESET}
   $QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_NET_PATH
   exit 1
fi

$QCOM_LN_RM_MK_DIR/cp -rf ./qcom_net/qmi.c $DEST_QCOM_NET_PATH
if [ ! -f $DEST_QCOM_NET_PATH/qmi.c ]; then
   echo -e ${RED}"Error: Failed to copy qmi.c to installation path, installation abort."${RESET}
   $QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_NET_PATH
   exit 1
fi

$QCOM_LN_RM_MK_DIR/cp -rf ./qcom_net/qmi.h $DEST_QCOM_NET_PATH
if [ ! -f $DEST_QCOM_NET_PATH/qmi.h ]; then
   echo -e ${RED}"Error: Failed to copy qmi.h to installation path, installation abort."${RESET}
   $QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_NET_PATH
   exit 1
fi

$QCOM_LN_RM_MK_DIR/cp -rf ./qcom_net/qmap.c $DEST_QCOM_NET_PATH
if [ ! -f $DEST_QCOM_NET_PATH/qmap.c ]; then
   echo -e ${RED}"Error: Failed to copy qmap.c to installation path, installation abort."${RESET}
   $QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_NET_PATH
   exit 1
fi

$QCOM_LN_RM_MK_DIR/cp -rf ./qcom_net/qmap.h $DEST_QCOM_NET_PATH
if [ ! -f $DEST_QCOM_NET_PATH/qmap.h ]; then
   echo -e ${RED}"Error: Failed to copy qmap.h to installation path, installation abort."${RESET}
   $QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_NET_PATH
   exit 1
fi

$QCOM_LN_RM_MK_DIR/cp -rf ./qcom_net/common.h $DEST_QCOM_NET_PATH
if [ ! -f $DEST_QCOM_NET_PATH/common.h ]; then
   echo -e ${RED}"Error: Failed to copy common.h to installation path, installation abort."${RESET}
   $QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_NET_PATH
   exit 1
fi

$QCOM_LN_RM_MK_DIR/cp -rf ./qcom_net/Makefile  $DEST_QCOM_NET_PATH
if [ ! -f $DEST_QCOM_NET_PATH/Makefile ]; then
   echo -e ${RED}"Error: Failed to copy Makefile installation path, installation abort."${RESET}
   $QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_NET_PATH
   exit 1
fi

#DEST_SIGN_PATH=/opt/qcom/QUD/sign
#OLD_DEST_SIGN_PATH=/opt/QTI/sign
if [[ -d $OLD_DEST_SIGN_PATH ]] && [[ -f $OLD_DEST_SIGN_PATH/Signkey_pub.der ]]; then
   QCOM_OLD_PUBLIC_KEY_VERIFY=`mokutil --test-key $OLD_DEST_SIGN_PATH/Signkey_pub.der`
   if [[ $QCOM_OLD_PUBLIC_KEY_VERIFY = "$OLD_DEST_SIGN_PATH/Signkey_pub.der is already enrolled" ]]; then
      $QCOM_LN_RM_MK_DIR/cp -rf $OLD_DEST_SIGN_PATH/* $DEST_SIGN_PATH/
      $QCOM_LN_RM_MK_DIR/chmod -R 777 $DEST_SIGN_PATH
      $QCOM_LN_RM_MK_DIR/chmod 644 $DEST_SIGN_PATH/signReadme.txt
      $QCOM_LN_RM_MK_DIR/chmod 755 $DEST_SIGN_PATH/Signkey_pub.der
      $QCOM_LN_RM_MK_DIR/chmod 755 $DEST_SIGN_PATH/Signkey.priv
   fi
elif [[ -d $DEST_SIGN_PATH ]]; then
   QCOM_PUBLIC_KEY_VERIFY=`mokutil --test-key $DEST_SIGN_PATH/Signkey_pub.der`
   if [[ $QCOM_PUBLIC_KEY_VERIFY = "$DEST_SIGN_PATH/Signkey_pub.der is already enrolled" ]]; then
      echo -e ${GREEN}"$DEST_SIGN_PATH/Signkey_pub.der is enrolled"${RESET}
   else
      echo -e ${RED}"Signkey_pub.der is not enrolled or doesn't exist"${RESET}
      $QCOM_LN_RM_MK_DIR/cp -rf ./sign/SignConf.config $DEST_SIGN_PATH
      $QCOM_LN_RM_MK_DIR/chmod 777 $DEST_SIGN_PATH/SignConf.config
      awk -i inplace -v name=`hostname` '{gsub(/O = /,"O = "name)}1' $DEST_SIGN_PATH/SignConf.config
      awk -i inplace -v name=`hostname` '{gsub(/CN = /,"CN = "name" Signing Key")}1' $DEST_SIGN_PATH/SignConf.config
      awk -i inplace -v name=`hostname` '{gsub(/emailAddress = /,"emailAddress = "name"@no-reply.com")}1' $DEST_SIGN_PATH/SignConf.config

      if [ ! -f $DEST_SIGN_PATH/SignConf.config ]; then
         echo -e ${RED}"Error: Failed to copy SignConf.config installation path, installation abort."${RESET}
         $QCOM_LN_RM_MK_DIR/rm -rf $DEST_SIGN_PATH
         exit 1
      fi

      $QCOM_LN_RM_MK_DIR/cp -rf ./sign/signReadme.txt $DEST_SIGN_PATH
      if [ ! -f $DEST_SIGN_PATH/signReadme.txt ]; then
         echo -e ${RED}"Error: Failed to copy signReadme.txt installation path, installation abort."${RESET}
         $QCOM_LN_RM_MK_DIR/rm -rf $DEST_SIGN_PATH
         exit 1
      fi
      $QCOM_LN_RM_MK_DIR/chmod 644 $DEST_SIGN_PATH/signReadme.txt
   fi
fi

if [[ $QCOM_SECURE_BOOT_CHECK = "SecureBoot enabled" ]]; then
   echo -e ${GREEN}"SecureBoot enabled"${RESET}
   QCOM_PUBLIC_KEY_VERIFY=`mokutil --test-key $DEST_SIGN_PATH/Signkey_pub.der`
   if [ -f $DEST_SIGN_PATH/Signkey_pub.der ]; then
      if [[ $QCOM_PUBLIC_KEY_VERIFY = "$DEST_SIGN_PATH/Signkey_pub.der is already enrolled" ]]; then
         echo -e ${CYAN}"==========================================================="
         echo -e ${GREEN}"$DEST_SIGN_PATH/Signkey_pub.der is enrolled"
         echo -e ${CYAN}"==========================================================="${RESET}
      else
         echo -e ${RED}"==========================================================="
         echo -e ${CYAN}"Secure Boot is enabled. Public key $DEST_SIGN_PATH/Signkey_pub.der enrolling failed!"
         echo -e ${CYAN}"Try again and follow mandatory instructions properly ($DEST_SIGN_PATH/signReadme.txt)"
         echo -e ${CYAN}"The QUD driver installation Failed!!!"
         echo -e ${RED}"==========================================================="${RESET}
         exit 1
      fi
   else
      echo -e ${RED}"Signkey_pub.der doesn't exist. Creating public and private key"${RESET}
      openssl req -x509 -new -nodes -utf8 -sha256 -days 36500 -batch -config $DEST_SIGN_PATH/SignConf.config -outform DER -out $DEST_SIGN_PATH/Signkey_pub.der -keyout $DEST_SIGN_PATH/Signkey.priv
      $QCOM_LN_RM_MK_DIR/chmod 755 $DEST_SIGN_PATH/Signkey_pub.der
      $QCOM_LN_RM_MK_DIR/chmod 755 $DEST_SIGN_PATH/Signkey.priv
      echo -e ${RED}"##############################################################"
      echo -e ${CYAN}"Secure Boot is enabled. User must enroll the Public Signkey located at $DEST_SIGN_PATH/Signkey_pub.der"
      echo -e ${CYAN}"Please follow the mandatory instructions in $DEST_SIGN_PATH/signReadme.txt"
      echo -e ${CYAN}"The QUD driver installation Failed!!!"
      echo -e ${RED}"##############################################################"${RESET}
      exit 1
   fi
else
   echo -e ${GREEN}"Secure boot disabled"${RESET}
fi

# "********************* Compilation of modules Starts ***************************"
$QCOM_MAKE_DIR/make build

if [ ! -f ./qcom_usb/$QCOM_USB_MODULE_NAME ]; then
   echo -e ${RED}"Error: Failed to generate kernel module $QCOM_USB_MODULE_NAME, installation abort."${RESET}
   exit 1
fi

if [ ! -f ./qcom_net/$QCOM_USBNET_MODULE_NAME ]; then
  echo -e ${RED}"Error: Failed to generate kernel module $QCOM_USBNET_MODULE_NAME, installation abort."${RESET}
  exit 1
fi

$QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_USB_PATH/$QCOM_USB_MODULE_NAME
$QCOM_LN_RM_MK_DIR/cp -rf ./qcom_usb/$QCOM_USB_MODULE_NAME $DEST_QCOM_USB_PATH
if [ ! -f $DEST_QCOM_USB_PATH/$QCOM_USB_MODULE_NAME ]; then
   echo -e ${RED}"Error: Failed to copy $QCOM_USB_MODULE_NAME to installation path, installation abort."${RESET}
   exit 1
fi

$QCOM_LN_RM_MK_DIR/rm -rf $DEST_QCOM_NET_PATH/$QCOM_USBNET_MODULE_NAME
$QCOM_LN_RM_MK_DIR/cp -rf ./qcom_net/$QCOM_USBNET_MODULE_NAME $DEST_QCOM_NET_PATH
if [ ! -f $DEST_QCOM_NET_PATH/$QCOM_USBNET_MODULE_NAME ]; then
  echo -e ${RED}"Error: Failed to copy $QCOM_USBNET_MODULE_NAME to installation path, installation abort."${RESET}
  exit 1
fi

echo SUBSYSTEMS==\"qcom_usbnet\", MODE=\"0666\" >> ./qcom-usb-devices.rules
echo SUBSYSTEMS==\"qcom_usb\", MODE=\"0666\" >> ./qcom-usb-devices.rules
echo SUBSYSTEMS==\"qcom_ports\", MODE=\"0666\" >> ./qcom-usb-devices.rules

$QCOM_LN_RM_MK_DIR/chmod 644 ./qcom-usb-devices.rules
$QCOM_LN_RM_MK_DIR/cp -rf ./qcom-usb-devices.rules $QCOM_UDEV_PATH
echo -e "Generated QC rules"

# udev rules for qmi
if [ -f $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules ]; then
   RULE_EXIST="`grep -nr  'usb' $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules`"
   if [ "$RULE_EXIST" != "" ]; then
      echo -e "Subsystem qcom_usbnet rule already exist in $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules, nothing to add"
   else
      echo -e "Subsystem qcom_usbnet rule doesn't exist in $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules, so adding now"
      $QCOM_LN_RM_MK_DIR/chmod 644 $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules
      echo SUBSYSTEMS==\"usb\", ATTRS{idVendor}==\"05c6\", NAME=\"usb%n\" >> $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules
   fi
else
   echo SUBSYSTEMS==\"usb\", ATTRS{idVendor}==\"05c6\", NAME=\"usb%n\" >> ./80-qcom-usbnet-devices.rules
   $QCOM_LN_RM_MK_DIR/chmod 644 ./80-qcom-usbnet-devices.rules
   $QCOM_LN_RM_MK_DIR/cp -rf ./80-qcom-usbnet-devices.rules $QCOM_UDEV_PATH
   echo -e "Creating new udev rule for qcom_usbnet in $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules"
fi

# Informs udev deamon to reload the newly added device rule and re-trigger service
sudo udevadm control --reload-rules
sudo udevadm trigger

if [ ! -f $QCOM_UDEV_PATH/qcom-usb-devices.rules ]; then
   echo -e ${RED}"Error: Failed to generate $QCOM_UDEV_PATH/qcom-usb-devices.rules"
   exit 1
fi

if [ ! -f $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules ]; then
   echo -e ${RED}"Error: Failed to generate $QCOM_UDEV_PATH/80-qcom-usbnet-devices.rules"
   exit 1
fi

rm -f ./qcom-usb-devices.rules
rm -f ./80-qcom-usbnet-devices.rules
echo -e "Removed local rules"

MODLOADED="`/sbin/lsmod | grep usbserial`"
if [ "$MODLOADED" == "" ]; then
   echo -e "To load dependency"
   echo -e "Loading module usbserial"
   if [[ $OSName =~ "Red Hat Enterprise Linux" ]]; then
      if [ -f $MODULE_BLACKLIST_PATH/usbserial.ko.xz ]; then
	xz -d $MODULE_BLACKLIST_PATH/usbserial.ko.xz 
      	$QCOM_MODBIN_DIR/insmod $MODULE_BLACKLIST_PATH/usbserial.ko
      fi
      MODLOADED="`/sbin/lsmod | grep usbserial`"
      if [ "$MODLOADED" == "" ]; then
        echo -e "$OSName: usbserial.ko module not present at $MODULE_BLACKLIST_PATH"
      fi
   else
	   $QCOM_MODBIN_DIR/insmod $MODULE_BLACKLIST_PATH/usbserial.ko
   fi
else
   echo -e "Module usbserial already in place"
fi

#echo Changing Permission of blacklist file
$QCOM_LN_RM_MK_DIR/chmod 777 $MODULE_BLACKLIST_CONFIG/blacklist.conf
echo -e "Changed Permission of blacklist file"
if [ "`grep -nr 'Qualcomm clients' /etc/modprobe.d/blacklist.conf`" != "" ]; then
   sed -i '/# Blacklist these module so that Qualcomm clients use only/d' /etc/modprobe.d/blacklist.conf
   sed -i '/# qcom_usbnet, qcom_usb driver/d' /etc/modprobe.d/blacklist.conf
fi
echo -e "# Blacklist these module so that Qualcomm clients use only" >> /etc/modprobe.d/blacklist.conf
echo -e "# qcom_usbnet, qcom_usb driver" >> /etc/modprobe.d/blacklist.conf

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
if [  -f $MODULE_BLACKLIST_PATH/qcserial.ko ]; then
   echo -e "qcserial is found. renamed to qcserial_dup"
   mv /lib/modules/`uname -r`/kernel/drivers/usb/serial/qcserial.ko /lib/modules/`uname -r`/kernel/drivers/usb/serial/qcserial_dup
fi

MOD_EXIST="`grep -nr  'blacklist qmi_wwan' /etc/modprobe.d/blacklist.conf`"
if [ "$MOD_EXIST" != "" ]; then
   sed -i '/qmi_wwan/d' $MODULE_BLACKLIST_CONFIG/blacklist.conf
fi
echo -e "blacklist qmi_wwan" >> /etc/modprobe.d/blacklist.conf
echo -e "install qmi_wwan /bin/false" >> /etc/modprobe.d/blacklist.conf
echo -e "blacklisted qmi_wwan module"

MODLOADED="`/sbin/lsmod | grep qmi_wwan`"
if [ "$MODLOADED" != "" ]; then
   echo -e "qmi_wwan is found. Unloaded qmi_wwan module"
   echo -e "cdc-wdm is found. Unloaded cdc-wdm module"
   $QCOM_MODBIN_DIR/rmmod qmi_wwan.ko
   $QCOM_MODBIN_DIR/rmmod cdc-wdm.ko
   MODLOADED="`/sbin/lsmod | grep qmi_wwan`"
   if [ "$MODLOADED" != "" ]; then
      echo -e ${RED}"Failed to unload qmi_wwan.ko. Run manually sudo rmmod ModuleName"${RESET}
   fi
   MODLOADED="`/sbin/lsmod | grep cdc_wdm`"
   if [ "$MODLOADED" != "" ]; then
      echo -e ${RED}"Failed to unload cdc_wdm.ko. Run manually sudo rmmod ModuleName"${RESET}
   fi
fi
if [  -f $QCOM_USBNET_AND_QMI_WWAN/qmi_wwan.ko ]; then
   echo -e "qmi_wwan is found. renamed to qmi_wwan_dup"
   echo -e "cdc-wdm is found. renamed to cdc-wdm_dup"
   mv /lib/modules/`uname -r`/kernel/drivers/usb/class/cdc-wdm.ko /lib/modules/`uname -r`/kernel/drivers/usb/class/cdc-wdm_dup
   mv /lib/modules/`uname -r`/kernel/drivers/net/usb/qmi_wwan.ko /lib/modules/`uname -r`/kernel/drivers/net/usb/qmi_wwan_dup
   depmod
fi

MOD_EXIST="`grep -nr  'blacklist option' /etc/modprobe.d/blacklist.conf`"
if [ "$MOD_EXIST" != "" ]; then
   sed -i '/option/d' $MODULE_BLACKLIST_CONFIG/blacklist.conf
fi
echo -e "blacklist option" >> /etc/modprobe.d/blacklist.conf
echo -e "install option /bin/false" >> /etc/modprobe.d/blacklist.conf
echo -e "blacklisted option module"

MODLOADED="`/sbin/lsmod | grep option`"
if [ "$MODLOADED" != "" ]; then
   echo -e "option is found. Unloaded option module"
   $QCOM_MODBIN_DIR/rmmod option.ko
   MODLOADED="`/sbin/lsmod | grep option`"
   if [ "$MODLOADED" != "" ]; then
      echo -e ${RED}"Failed to unload option.ko. Run manually sudo rmmod option"${RESET}
   fi
fi
if [  -f $MODULE_BLACKLIST_PATH/option.ko ]; then
   echo -e "option is found. renamed to to option_dup"
   mv /lib/modules/`uname -r`/kernel/drivers/usb/serial/option.ko /lib/modules/`uname -r`/kernel/drivers/usb/serial/option_dup
fi

MOD_EXIST="`grep -nr  'blacklist usb_wwan' /etc/modprobe.d/blacklist.conf`"
if [ "$MOD_EXIST" != "" ]; then
   sed -i '/usb_wwan/d' $MODULE_BLACKLIST_CONFIG/blacklist.conf
fi
echo -e "blacklist usb_wwan" >> /etc/modprobe.d/blacklist.conf
echo -e "install usb_wwan /bin/false" >> /etc/modprobe.d/blacklist.conf
echo -e "blacklisted usb_wwan module"

MODLOADED="`/sbin/lsmod | grep usb_wwan`"
if [ "$MODLOADED" != "" ]; then
   echo -e "usb_wwan is found. Unloaded usb_wwan module"
   $QCOM_MODBIN_DIR/rmmod usb_wwan.ko
   MODLOADED="`/sbin/lsmod | grep usb_wwan`"
   if [ "$MODLOADED" != "" ]; then
      echo -e ${RED}"Failed to unload usb_wwan.ko. Run manually sudo rmmod ModuleName"${RESET}
   fi
fi
if [  -f $MODULE_BLACKLIST_PATH/usb_wwan.ko ]; then
   echo -e "usb_wwan is found. renamed to usb_wwan_dup"
   mv /lib/modules/`uname -r`/kernel/drivers/usb/serial/usb_wwan.ko /lib/modules/`uname -r`/kernel/drivers/usb/serial/usb_wwan_dup
fi

MODLOADED="`/sbin/lsmod | grep qcom_usb`"
if [ "$MODLOADED" != "" ]; then
   ($QCOM_MODBIN_DIR/rmmod $QCOM_USB_MODULE_NAME && echo -e "$QCOM_USB_MODULE_NAME removed successfully..") ||  { echo -e "$QCOM_USB_MODULE_NAME in use"; echo -e ${RED}"Note: ${CYAN} Close all applications that make use of the driver, including QUTS clients."; echo -e ${RED}"ps -aux | grep QUTS, sudo kill -9 <PID> OR sudo pkill QUTS"; echo -e ${GREEN}"Try $1ation again!"${RESET}; exit 1; }
fi

echo -e "Loading $QCOM_USBNET_MODULE_NAME module dependency"
MODLOADED="`/sbin/lsmod | grep mii`"
if [ "$MODLOADED" == "" ]; then
   echo -e "Loading module mii"
   if [[ $OSName =~ "Red Hat Enterprise Linux" ]] || [[ $OSName =~ "Fedora Linux" ]] || [[ $OSName =~ "Ubuntu 24.04" ]]; then
      if [ -f $QCOM_NET_DEPENDENCY_PATH/mii.ko.xz ]; then
        xz -d $QCOM_NET_DEPENDENCY_PATH/mii.ko.xz
      fi
      if [ -f $QCOM_NET_DEPENDENCY_PATH/mii.ko.zst ]; then
        unzstd -d $QCOM_NET_DEPENDENCY_PATH/mii.ko.zst
      fi
      if [ -f $QCOM_NET_DEPENDENCY_PATH/mii.ko ]; then
         $QCOM_MODBIN_DIR/insmod $QCOM_NET_DEPENDENCY_PATH/mii.ko
      fi
      MODLOADED="`/sbin/lsmod | grep mii`"
      if [ "$MODLOADED" == "" ]; then
        echo -e "$OSName: mii.ko module not present at $QCOM_NET_DEPENDENCY_PATH"
      fi
   else
      if [ -f $QCOM_NET_DEPENDENCY_PATH/mii.ko ]; then
         $QCOM_MODBIN_DIR/insmod $QCOM_NET_DEPENDENCY_PATH/mii.ko
      else
         echo -e "$OSName: mii.ko module not present at $QCOM_NET_DEPENDENCY_PATH"
      fi
   fi
else
   echo -e "Module mii already in place"
fi

MODLOADED="`/sbin/lsmod | grep usbnet`"
if [ "$MODLOADED" == "" ]; then
   echo -e "Loading module usbnet"
   if [[ $OSName =~ "Red Hat Enterprise Linux" ]] || [[ $OSName =~ "Fedora Linux" ]] || [[ $OSName =~ "Ubuntu 24.04" ]]; then
      if [ -f $QCOM_USBNET_AND_QMI_WWAN/usbnet.ko.xz ]; then
        xz -d $QCOM_USBNET_AND_QMI_WWAN/usbnet.ko.xz
      fi
      if [ -f $QCOM_USBNET_AND_QMI_WWAN/usbnet.ko.zst ]; then
        unzstd -d $QCOM_USBNET_AND_QMI_WWAN/usbnet.ko.zst
      fi
      if [ -f $QCOM_USBNET_AND_QMI_WWAN/usbnet.ko ]; then
         $QCOM_MODBIN_DIR/insmod $QCOM_USBNET_AND_QMI_WWAN/usbnet.ko
      fi
      MODLOADED="`/sbin/lsmod | grep usbnet`"
      if [ "$MODLOADED" == "" ]; then
        echo -e "$OSName: usbnet.ko module not present at $QCOM_USBNET_AND_QMI_WWAN"
      fi
   else
      if [ -f $QCOM_USBNET_AND_QMI_WWAN/usbnet.ko ]; then
   	   $QCOM_MODBIN_DIR/insmod $QCOM_USBNET_AND_QMI_WWAN/usbnet.ko
      else
         echo -e "$OSName: usbnet.ko module not present at $QCOM_USBNET_AND_QMI_WWAN"
      fi
   fi
else
   echo -e "Module usbnet already in place"
fi

MODLOADED="`/sbin/lsmod | grep qcom_usbnet`"
if [ "$MODLOADED" != "" ]; then
  ($QCOM_MODBIN_DIR/rmmod $QCOM_USBNET_MODULE_NAME && echo -e "$QCOM_USBNET_MODULE_NAME removed successfully..") || { echo -e "$QCOM_USBNET_MODULE_NAME in use"; echo -e ${RED}"Note: ${CYAN} Close all applications that make use of the driver, including QUTS clients."; echo -e ${RED}"ps -aux | grep QUTS, sudo kill -9 <PID> OR sudo pkill QUTS"; echo -e ${GREEN}"Try $1ation again!"${RESET}; exit 1; }
fi

echo -e "Loading new module $QCOM_USB_MODULE_NAME"
$QCOM_MODBIN_DIR/insmod $DEST_QCOM_USB_PATH/$QCOM_USB_MODULE_NAME
MODLOADED="`/sbin/lsmod | grep qcom_usb`"
if [ "$MODLOADED" == "" ]; then
   echo -e ${RED}"Failed to load new $QCOM_USB_MODULE_NAME module"${RESET}
   exit 1
fi
echo -e "Loading new module $QCOM_USBNET_MODULE_NAME"
$QCOM_MODBIN_DIR/insmod $DEST_QCOM_NET_PATH/$QCOM_USBNET_MODULE_NAME debug_g=1 debug_aggr=0
MODLOADED="`/sbin/lsmod | grep qcom_usbnet`"
if [ "$MODLOADED" == "" ]; then
   echo -e ${RED}"Failed to load new $QCOM_USBNET_MODULE_NAME module"${RESET}
   #exit 1
fi

$QCOM_LN_RM_MK_DIR/rm -rf $QCOM_USB_KERNEL_PATH/$QCOM_USB_MODULE_NAME
$QCOM_LN_RM_MK_DIR/cp -rf $DEST_QCOM_USB_PATH/$QCOM_USB_MODULE_NAME $QCOM_USB_KERNEL_PATH
if [ ! -f $QCOM_USB_KERNEL_PATH/$QCOM_USB_MODULE_NAME ]; then
   echo -e ${RED}"Error: Failed to copy $QCOM_USB_MODULE_NAME to $QCOM_USB_KERNEL_PATH path."${RESET}
   exit 1
fi

$QCOM_LN_RM_MK_DIR/rm -rf $QCOM_USBNET_AND_QMI_WWAN/$QCOM_USBNET_MODULE_NAME
$QCOM_LN_RM_MK_DIR/cp -rf $DEST_QCOM_NET_PATH/$QCOM_USBNET_MODULE_NAME $QCOM_USBNET_AND_QMI_WWAN
if [ ! -f $QCOM_USBNET_AND_QMI_WWAN/$QCOM_USBNET_MODULE_NAME ]; then
  echo -e ${RED}"Error: Failed to copy $QCOM_USBNET_MODULE_NAME to $QCOM_USBNET_AND_QMI_WWAN path."${RESET}
  exit 1
fi

# update modules.dep and modules.alias
depmod

# Enable debug messages for qcom_usb driver
# Note: For qcom_usbnet, command will enable debug messages only for 1 device
if [[ "$QCOM_DRIVER_DEBUG_ENABLE" = "qcom_usb" ]]; then
   echo "module qcom_usb +p" > /sys/kernel/debug/dynamic_debug/control
   echo -e "Enable debug messages for qcom_usb driver"
elif [[ "$QCOM_DRIVER_DEBUG_ENABLE" = "qcom_usbnet" ]]; then
   echo 0F02 > /sys/QCOM_WWAN_Adapter_*:*usb0_0/Debug
   echo -e "Enable debug messages for qcom_usbnet driver"
elif [[ "$QCOM_DRIVER_DEBUG_ENABLE" = "all" ]]; then
   echo "module qcom_usb +p" > /sys/kernel/debug/dynamic_debug/control
   echo 0F02 > /sys/QCOM_WWAN_Adapter_*:*usb0_0/Debug
   echo -e "Enable debug messages for qcom_usb, qcom_usbnet driver"
else
   echo -e "No debug message enabled"
fi

$QCOM_MAKE_DIR/make clean

$QCOM_MAKE_DIR/find $DEST_QUD_PATH -type d -exec chmod 0755 {} \;

echo -e "Qualcomm qcom_usbnet driver is installed at $DEST_QCOM_NET_PATH"
echo -e "Qualcomm qcom_usb driver is installed at $DEST_QCOM_USB_PATH"
echo -e "Qualcomm udev naming/permission rules are installed at $QCOM_UDEV_PATH"

if [ -f "$DEST_QUD_PATH/ReleaseNotes*.txt" ]; then
   echo -e "QUD Release Notes available at $DEST_QUD_PATH"
fi

MODUPDATE="`grep -nr  qcom_usb /etc/modules`"
if [ "$MODUPDATE" == "" ]; then
	echo -e "qcom_usb" >> /etc/modules
fi

MODUPDATE="`grep -nr  qcom_usbnet /etc/modules`"
if [ "$MODUPDATE" == "" ]; then
	echo -e "qcom_usbnet" >> /etc/modules
fi

if [[ $OSName != *"Red Hat Enterprise Linux"* ]]; then
   MODUPDATE="`grep -nr  'iface usb0 inet static' /etc/network/interfaces`"
   if [ "$MODUPDATE" == "" ]; then
	echo -e "iface usb0 inet static" >> /etc/network/interfaces
  fi
fi

exit 0
