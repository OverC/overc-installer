######################################################################
# Define some configuration variables

## Installer file locations
INSTALLER_FILES_DIR="/inst/images/"
INSTALLER_SBIN_DIR="/inst/installer/sbin"

INSTALL_KERNEL="${INSTALLER_FILES_DIR}/bzImage"
INSTALL_ROOTFS="${INSTALLER_FILES_DIR}/op3-graphical-builder-genericx86-64.tar.bz2"
INSTALL_MODULES=""

INSTALL_GRUBHDCFG="${INSTALLER_FILES_DIR}/grub-hd.cfg"
INSTALL_GRUBUSBCFG="${INSTALLER_FILES_DIR}/grub-usb.cfg"
INSTALL_GRUBCFG="${INSTALL_GRUBHDCFG}"

INSTALL_FILES="${INSTALL_KERNEL} ${INSTALL_ROOTFS} ${INSTALL_MODULES} ${INSTALL_GRUBCFG}"

## List of prerequisite files for the installer to check
PREREQ_FILES="${INSTALL_FILES}"

BOARD_NAME="genericx86"
EVAL_NAME="Nucleo-T Evaluation"

HARDDRIVE_DEVICE="/sys/class/scsi_disk/0:0:0:0/device"
HARDDRIVE_MODEL="ST9120822SB     "

BOOTPART_START="0"
BOOTPART_END="250M"
BOOTPART_FSTYPE="fat32"
BOOTPART_LABEL="boot"

ROOTFS_START="250M"
ROOTFS_END="-1"	# Specify -1 to use the rest of drive
ROOTFS_FSTYPE="ext2"
ROOTFS_LABEL="rootfs"

HARDDRIVE_BANNER="Wind River Hard Drive Installer
--------------------------------------------------------------------------------
$EVAL_NAME
--------------------------------------------------------------------------------"

HARDDRIVE_INTRODUCTION="
This installer will erase all data on your hard drive and configure it to boot
a working Nucleo-T
"

INSTALLER_COMPLETE="Installation is now complete"

CONFIRM_REBOOT=1

CMD_GRUB_INSTALL="/bin/bash /sbin/grub-install"

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
