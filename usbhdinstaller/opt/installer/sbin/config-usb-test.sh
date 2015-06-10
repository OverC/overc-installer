######################################################################
# Define some configuration variables

## Installer file locations
INSTALLER_FILES_DIR="/home/bruce/git/usbhdinstaller/usbhdinstaller/opt/installer/files"
INSTALLER_TARGET_FILES_DIR="/opt/installer/files"
INSTALLER_SCRIPTS_DIR="/home/bruce/git/usbhdinstaller/usbhdinstaller/opt/installer/scripts"
INSTALLER_SBIN_DIR="/home/bruce/git/usbhdinstaller/usbhdinstaller/opt/installer/sbin"
INSTALLER_TARGET_SBIN_DIR="/opt/installer/sbin"

# ARTIFACTS_DIR="/home/bruce/poky-yocto-builder/build/tmp/deploy/images/genericx86-64"
ARTIFACTS_DIR="/home/bruce/poky-yocto-builder/build/tmp/deploy/images/genericx86-64"
# PACKAGES_DIR="/home/bruce/poky-yocto-builder/build/tmp/deploy/rpm"

INSTALL_KERNEL="${ARTIFACTS_DIR}/bzImage"
INSTALL_ROOTFS=""
INSTALL_MODULES=""
INSTALL_INITRAMFS="${ARTIFACTS_DIR}/pod-builder-initramfs-genericx86-64.cpio.gz"

INSTALL_GRUBHDCFG="${INSTALLER_FILES_DIR}/grub-hd.cfg"
INSTALL_GRUBUSBCFG="${INSTALLER_FILES_DIR}/grub-usb.cfg"
INSTALL_GRUBCFG="${INSTALL_GRUBUSBCFG}"
INSTALL_IMAGE_DIR="/inst/"

INSTALL_FILES="${INSTALL_KERNEL} ${INSTALL_ROOTFS} ${INSTALL_MODULES} ${INSTALL_GRUBCFG}"

PROJECT_WRLINUX_ROOTFS=""
PROJECT_WRLINUX_MODULES=""
PROJECT_FILES=""

HDINSTALL_ROOTFS="${ARTIFACTS_DIR}/pod-graphical-builder-genericx86-64.tar.bz2"

## List of prerequisite files for the installer to check
# PREREQ_FILES="${INSTALL_FILES} ${PROJECT_FILES}"
PREREQ_FILES="${INSTALL_FILES}"

BOARD_NAME="Generic x86"
EVAL_NAME="Evaluation - Wind River POD"

BOOTPART_START="63s"
BOOTPART_END="250M"
BOOTPART_FSTYPE="fat32"
BOOTPART_LABEL="boot"

ROOTFS_START="250M"
ROOTFS_END="-1"	# Specify -1 to use the rest of drive
ROOTFS_FSTYPE="ext2"
ROOTFS_LABEL="rootfs"

USBSTORAGE_BANNER="Wind River USB Creator for the Hard Drive Installer
--------------------------------------------------------------------------------
$EVAL_NAME
--------------------------------------------------------------------------------"

USBSTORAGE_INTRODUCTION="
This script will erase all data on your USB flash drive and configure it to boot
the Wind River Hard Drive Installer.  This installer will then allow you to
install a working system configuration on to your internal hard drive.
"

INSTALLER_COMPLETE="Installation is now complete"

CONFIRM_REBOOT=0

CMD_GRUB_INSTALL="/usr/sbin/grub-install"

######################################################################
# Define some debug output variables

# Debug Levels - fixed values
DEBUG_SILENT=0
DEBUG_CRIT=1
DEBUG_WARN=2
DEBUG_INFO=4
DEBUG_VERBOSE=7

# Set your default debug level
: ${DEBUG_DEFAULT:=${DEBUG_INFO}}

# Dynamic debug level
DEBUG_LEVEL=${DEBUG_DEFAULT}

: ${TRACE:=0}
