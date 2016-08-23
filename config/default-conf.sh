###########################################################################
# This file is the default configuration file for the overc-installer
# 
# For each configuration item, there are explainations and sample values
# provided. When you are writing your own config file, you can just set the
# parameters that have different values other than defaults.

###############################################################################
# Generic settings
###############################################################################

# The evaluation name and the distribution name of the install
# They will be put in display text and the grub bootloader title
EVAL_NAME="Evaluation - Nucleo-T"
DISTRIBUTION="OverC"

# The board name of the installer.
# In the sbin dir of this installer, if board specific functions are available,
# they will be named as function-${BOARD_NAME}.sh
BOARD_NAME="generic-overc-board"

# The confirmations for user
CONFIRM_INSTALL=1
CONFIRM_REBOOT=0

###############################################################################
# Intallation parameters
###############################################################################

# When set, the initramfs specified by INSTALL_INITRAMFS variable will be
# repacked with the extras.
INITRAMFS_EXTRAS=""

# The location of artifacts, including the kernel, image, etc.
# Default to the first image output dir.
# If there are multiple architecture of this project, please make sure that
# you are using the corrects artifacts.
ARTIFACTS_DIR=`pwd`/tmp/deploy/images/`ls tmp/deploy/images/ -1 | head -n 1`

# Prerequisite files
INSTALL_KERNEL="${ARTIFACTS_DIR}/bzImage"
INSTALL_MODULES=""

INSTALL_INITRAMFS="${ARTIFACTS_DIR}/`ls -1 ${ARTIFACTS_DIR} | grep -e 'initramfs.*cpio' | grep -v 'rootfs'`"
INSTALL_ROOTFS="${ARTIFACTS_DIR}/`ls -1 ${ARTIFACTS_DIR} | grep -e 'essential.*tar' | grep -v 'rootfs'`"

# EFI file location. Will use startup.nsh if not found
INSTALL_EFIBOOT="${ARTIFACTS_DIR}/bootx64.efi"

# The smart config file which has been set the smart channels.
# It should be put in the ${ARTIFACTS_DIR}
INSTALL_SMARTCONFIG="${ARTIFACTS_DIR}/config"

# Extra packages to be installed
PACKAGES_DIR=""

# The ROOTFSs to be installed to the hard drive through the USB installer
# Default to essential rootfs.
HDINSTALL_ROOTFS="${ARTIFACTS_DIR}/`ls -1 ${ARTIFACTS_DIR} | grep -e 'essential.*tar' | grep -v 'rootfs'`"

# The containers to be installed to the hard drive through the USB installer
# They should be put in the ${ARTIFACTS_DIR} or ${ARTIFACTS_DIR}/containers
# Every container can be followed by a list of properties:
#   vty: the virtual terminal allocated to this container
#   mergepath: the paths to be merged using overlayfs between containers
#   subuid: the start subuid for the container, make it unprivileged container
#           in the root namespace
#HDINSTALL_CONTAINERS="${ARTIFACTS_DIR}/cube-dom0-genericx86-64.tar.bz2:vty=2:mergepath=/usr,essential \
#                      ${ARTIFACTS_DIR}/cube-dom1-genericx86-64.tar.bz2:vty=3:mergepath=/usr,essential,dom0 \
#                      ${ARTIFACTS_DIR}/cube-desktop-genericx86-64.tar.bz2:vty=4:net=1:mergepath=/usr,essential,dom0,dom1 \
#                      ${ARTIFACTS_DIR}/cube-server-genericx86-64.tar.bz2:subuid=800000"
#

###############################################################################
# Boot parameters
###############################################################################

# Partition related
# This is the default partition layout for USB installer.
BOOTPART_START="63s"
BOOTPART_END="250M"
BOOTPART_FSTYPE="fat32"
BOOTPART_LABEL="OVERCBOOT"

ROOTFS_START="250M"
ROOTFS_END="-1"	# Specify -1 to use the rest of drive
ROOTFS_FSTYPE="ext2"
ROOTFS_LABEL="OVERCINSTROOTFS"

# The grub command to install. The default value is the system's version.
CMD_GRUB_INSTALL=`which grub-install`

# Hard Drive grub configuration
INSTALL_GRUBHDCFG="grub-hd.cfg"

# USB Installer grub configuration
INSTALL_GRUBUSBCFG="grub-usb.cfg"

## Uncomment for grub legacy
#INSTALL_GRUBUSBCFG="menu.lst.initramfs-installer"

# Define your own grub config
#INSTALL_GRUBCFG="${INSTALLER_FILES_DIR}/${INSTALL_GRUBUSBCFG}"

###############################################################################
# Target configurations
###############################################################################

# List of services to be disabled for each components
# It could be the service name, service file name or
# file globs. e.g. xinetd, named.service, nfs-*
#
# For essential and dom0
#SERVICE_DISABLE_ESSENTIAL=" \
#  xinetd \
#"
#SERVICE_DISABLE_DOM0=" \
#  tcf-agent \
#  xinetd \
#  crond \
#"

# For all containers
#SERVICE_DISABLE_CONTAINER=" \
#  nfs-* \
#  named \
#"
#SERVICE_CONDITION_CONTAINER=" \
#  watchdog \
#"

# Network devices to be passed to the designated network prime container
# Default to all network devices
NETWORK_DEVICE="all"

# Uncomment to specify path to init.pp
#INSTALL_PUPPET_DIR="puppet"

###############################################################################
# Text related parameters
###############################################################################

# Banner displayed when creating the USB Installer
USBSTORAGE_BANNER="USB Creator for the Hard Drive Installer
------------------------------------------------------------------------------
$EVAL_NAME
------------------------------------------------------------------------------"

# Introduction displayed when creating the USB Installer
USBSTORAGE_INTRODUCTION="
This script will erase all data on your USB flash drive and configure it to
boot the Wind River Hard Drive Installer.  This installer will then allow you
to install a working system configuration on to your internal hard drive.
"

# Banner displayed when creating the Hard Drive Installer
HARDDRIVE_BANNER="Wind River Hard Drive Installer
------------------------------------------------------------------------------
$EVAL_NAME
------------------------------------------------------------------------------"

# Introduction displayed when creating the Hard Drive Installer
HARDDRIVE_INTRODUCTION="
This installer will erase all data on your hard drive and configure it to boot
a working Nucleo-T
"

# Text to display when installation is finished
INSTALLER_COMPLETE="Installation is now complete"

###############################################################################
# Debug related parameters
###############################################################################

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

