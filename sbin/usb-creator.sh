#!/bin/bash

#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2 as
#  published by the Free Software Foundation.

#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#  See the GNU General Public License for more details.

BASEDIR=$(dirname $BASH_SOURCE)

: ${CONFIG_FILE="$BASEDIR/config-usb.sh"}
: ${FUNCTIONS_FILE="$BASEDIR/functions.sh"}

usage()
{
cat << EOF

  usb-creator.sh [--config <config script>] [<artifacts dir>] <block device>

  Create a bootable USB device based on the configuration found in
  ~/.overc/config-usb.sh, or the command line specified configuration
  script. 

  See the builtin example config-usb.sh.sample for what must be in a config script.

  examples:
    
      # network block device
      $ usb-creator.sh /dev/nbd0

      # usb drive as sdc
      $ usb-creator.sh /dev/sdc

      # network block device
      $ usb-creator.sh --config /tmp/my_usb_config.sh /dev/nbd0

EOF
}

if [ -z "$1" ]; then
    usage
    exit
fi

while [ $# -gt 0 ]; do
    case "$1" in
    --config) 
            CONFIG_FILE="$2"
	    shift
            ;;
    -o)     outpath=$2
            shift
            ;;
    -v) verbose=t
            ;;
         *) break
            ;;
    esac
    shift
done

# support files
INSTALLER_FILES_DIR="${BASEDIR}/../files"
# sbin files (typically this creator)
INSTALLER_SBIN_DIR="${BASEDIR}/../sbin"
# installers that will go on the usb stick, and install to the HD
INSTALLERS_DIR="${BASEDIR}/../installers"
# configuration for this script
CONFIG_DIRS="${BASEDIR}/../config $HOME/.overc/"

# command line parameters can be:
#   <artifacts dir>
#   <block device>
if [ -z "$1" ]; then
    debugmsg ${DEBUG_CRIT} "Please specify device"
    false
    assert $?
else   
    # if the first parameter is a directory, it is an artifacts dir,
    # otherwise, it is a block device
    if [ -d "$1" ]; then
	ARTIFACTS_DIR="$1"
	shift
    fi
    USBSTORAGE_DEVICE=/sys/block/$(basename "$1")
fi

## Load configuration file
CONFIGS_TO_SOURCE="${CONFIG_FILE}"
if ! [ -e $CONFIG_FILE ]; then
    CONFIGS_TO_SOURCE=""
    for d in ${CONFIG_DIRS}; do
	if [ -e "${d}/${CONFIG_FILE}" ]; then
	    CONFIGS_TO_SOURCE="${CONFIGS_TO_SOURCE} ${d}/$CONFIG_FILE"
	fi
    done

    if [ -z "${CONFIGS_TO_SOURCE}" ]; then
	echo "ERROR: Could not find configuration file (${CONFIG_FILE})."
	echo "Try using an absolute path or the file must be in one of ($(echo ${CONFIG_DIRS} | tr ' ' ','))."
	exit 1
    fi
else
    # Convert to abs path
    if [[ "$CONFIG_FILE" != /* ]]; then
        CONFIGS_TO_SOURCE="$(pwd)/${CONFIGS_TO_SOURCE}"
    fi
fi

old_pwd=`pwd`
for d in ${CONFIGS_TO_SOURCE}; do
    cd `dirname $d`
    source ${CONFIGS_TO_SOURCE}
done
cd $old_pwd

# Find the grub configuration
for d in ${CONFIG_DIRS} ${INSTALLER_FILES_DIR}; do
    if [ -e "${d}/${INSTALL_GRUBUSBCFG}" ] &&
       [ -z "${INSTALL_GRUBCFG}" ]; then
	INSTALL_GRUBCFG=${d}/${INSTALL_GRUBUSBCFG}
    fi
done
if [ -z "${INSTALL_GRUBUSBCFG}" ]; then
    echo "ERROR: usb grub configuration ${INSTALL_GRUBUSBCFG} not found"
    exit 1
fi

# Locations on the USB bootable drive fr installer configuration
if [ -z "${INSTALLER_TARGET_DIR}" ]; then
    INSTALLER_TARGET_DIR="/opt/installer"
fi
INSTALLER_TARGET_SBIN_DIR="${INSTALLER_TARGET_DIR}/sbin"
INSTALLER_TARGET_FILES_DIR="${INSTALLER_TARGET_DIR}/files"
INSTALLER_TARGET_IMAGES_DIR="${INSTALLER_TARGET_DIR}/images"

## Load functions file
if ! [ -e $FUNCTIONS_FILE ]
then
	echo "ERROR: Could not find function definitions (${FUNCTIONS_FILE})"
	exit 1
fi

source $FUNCTIONS_FILE

## Set up trap handler

trap_cmd='trap_handler $?'
trap "${trap_cmd}" EXIT

if [ -n ${USBSTORAGE_DEVICE} ]; then
    dev=$(validate_usbstorage "${USBSTORAGE_DEVICE}")
    if [ -z "$dev" ]; then
	# is it NBD ?
	echo "${USBSTORAGE_DEVICE}" | grep -q "nbd"
	if [ $? -eq 0 ]; then
	    dev=`basename "${USBSTORAGE_DEVICE}"`
	fi
    fi
    INSTALLER_BANNER=${USBSTORAGE_BANNER}
    INSTALLER_INTRODUCTION=${USBSTORAGE_INTRODUCTION}
else
    debugmsg ${DEBUG_CRIT} "No storage device provided"
    false
    assert $?
fi

if [ -z $dev ]; then
	debugmsg ${DEBUG_CRIT} "ERROR: Failed to detect device"
	false
	assert $?
fi

install_summary()
{
    package_count=0
    if [ -d "${PACKAGES_DIR}" ]; then
        package_count=`find ${PACKAGES_DIR} -name '*.rpm' | wc -l`
    fi

    echo ""
    echo "Install Summary:"
    echo "----------------"
    echo ""
    echo "   target device:"
    echo "             ${USBSTORAGE_DEVICE}"
    echo "   kernel:"
    echo "             ${INSTALL_KERNEL}"
    echo "   images: "
    for i in ${HDINSTALL_ROOTFS}; do
        echo "             `basename ${i}`"
    done
    echo "   packages: "
    echo "             $package_count packages available from: ${PACKAGES_DIR}"
    echo "   containers: "
    for i in ${HDINSTALL_CONTAINERS}; do
        echo "             `basename ${i}`"
    done
    echo ""

}

custom_install_rules()
{
	local mnt_boot="$1"
	local mnt_rootfs="$2"

	## repack initramfs as required
	local initramfs_source=${INSTALL_INITRAMFS}
	if [ -n "${INITRAMFS_EXTRAS}" ]; then
	    debugmsg ${DEBUG_INFO} "Repacking initramfs with extras"
	    sudo rm -rf /tmp/tt/
	    sudo mkdir -p /tmp/tt
	    cd /tmp/tt
	    sudo sh -c "zcat ${INSTALL_INITRAMFS} |cpio -id"
	    for helper in ${INITRAMFS_EXTRAS}; do
		if [ -e	"${helper}" ]; then
		    debugmsg ${DEBUG_INFO} "adding $helper to the initramfs"
		    cp "${helper}" .
		else
		    debugmsg ${DEBUG_INFO} "WARNING: could not find helper $helper"
		fi
	    done
	    find . | cpio -o -H newc > /tmp/new-initramfs
	    initramfs_source="/tmp/new-initramfs"
	fi

	## Copy kernel and files to filesystem 
	## Note: we always make sure to install the initramfs as
	##       INSTALL_INITRAMFS, since other routines read that global variable,
	##       and align things like grub to that name.
	debugmsg ${DEBUG_INFO} "Copying kernel image"
	install_kernel "${INSTALL_KERNEL}" "${mnt_boot}" "${initramfs_source}" "`basename ${INSTALL_INITRAMFS}`"
	assert_return $?

	if [ -n "${INSTALL_ROOTFS}" ]; then
	    debugmsg ${DEBUG_INFO} "Extracting root filesystem (${INSTALL_ROOTFS})"
	    extract_tarball "${INSTALL_ROOTFS}" "${mnt_rootfs}"
	    assert_return $?
	else
	    debugmsg ${DEBUG_INFO} "No rootfs specified, not extracting"
	fi
	
	if [ -n "${INSTALL_MODULES}" ]; then
	    debugmsg ${DEBUG_INFO} "Extracting kernel modules "
	    extract_tarball "${INSTALL_MODULES}" "${mnt_rootfs}"
	    assert_return $?
	else
	    debugmsg ${DEBUG_INFO} "No kernel modules specified, not extracting"
	fi

	recursive_mkdir ${mnt_rootfs}${INSTALLER_TARGET_SBIN_DIR}
	assert_return $?

	cp ${INSTALLER_SBIN_DIR}/* ${mnt_rootfs}${INSTALLER_TARGET_SBIN_DIR}
	if [ $? -ne 0 ]; then
		debugmsg ${DEBUG_CRIT} "ERROR: Failed to copy sbin files"
		return 1
	fi

	# put the installers in with the sbin files
	cp ${INSTALLERS_DIR}/* ${mnt_rootfs}${INSTALLER_TARGET_SBIN_DIR}
	if [ $? -ne 0 ]; then
		debugmsg ${DEBUG_CRIT} "ERROR: Failed to copy installer files"
		return 1
	fi

	## Copy files from local workspace to USB drive
	recursive_mkdir ${mnt_rootfs}${INSTALLER_TARGET_FILES_DIR}
	assert_return $?

	recursive_mkdir ${mnt_rootfs}${INSTALLER_TARGET_IMAGES_DIR}
	assert_return $?

	## Copy the hard drive GRUB configuration
	for d in ${CONFIG_DIRS} ${INSTALLER_FILES_DIR}; do
	    if [ -e ${d}/${INSTALL_GRUBHDCFG} ] &&
	       [ ! -e ${mnt_rootfs}${INSTALLER_TARGET_FILES_DIR}/${INSTALL_GRUBHDCFG} ]; then
		debugmsg ${DEBUG_CRIT} "INFO: found grub hd configuration ${d}/${INSTALL_GRUBHDCFG}"
		cp ${d}/${INSTALL_GRUBHDCFG} ${mnt_rootfs}${INSTALLER_TARGET_FILES_DIR}/${INSTALL_GRUBHDCFG}
	    fi
	done

	## Copy the efi grub
	if [ -n "${INSTALL_EFIBOOT}" ]; then
		debugmsg ${DEBUG_CRIT} "INFO: copy efi boot grub"
		cp "${INSTALL_EFIBOOT}" ${mnt_rootfs}${INSTALLER_TARGET_IMAGES_DIR}
	fi

	## And the installer kernel + initramfs
	cp "${INSTALL_KERNEL}" "${INSTALL_INITRAMFS}" ${mnt_rootfs}${INSTALLER_TARGET_IMAGES_DIR}

	## ----------------------------------------------------------
	## Things that will be installed to the hard drive below here
	## ----------------------------------------------------------
	if [ -n "${HDINSTALL_ROOTFS}" ]; then
	    ## Copy the Linux rootfs tarball(s) to USB drive
            for i in ${HDINSTALL_ROOTFS}; do               
	        cp ${i} ${mnt_rootfs}${INSTALLER_TARGET_IMAGES_DIR}
	        if [ $? -ne 0 ]; then
		    debugmsg ${DEBUG_CRIT} "ERROR: Failed to copy hard drive install root filesystem"
		    return 1
	        fi
            done
	fi

	# deal with any packages
	if [ -n "${PACKAGES_DIR}" ]; then
	    debugmsg ${DEBUG_INFO} "Copying RPMs to install media"
	    recursive_mkdir ${mnt_rootfs}/${INSTALLER_TARGET_IMAGES_DIR}/packages
	    cp -r ${PACKAGES_DIR} ${mnt_rootfs}/${INSTALLER_TARGET_IMAGES_DIR}/packages
	fi

	# containers
	if [ -n "${HDINSTALL_CONTAINERS}" ]; then
	    debugmsg ${DEBUG_INFO} "Copying Containers to install media"
	    recursive_mkdir ${mnt_rootfs}/${INSTALLER_TARGET_IMAGES_DIR}/containers
	    for c in ${HDINSTALL_CONTAINERS}; do
		cp ${c} ${mnt_rootfs}/${INSTALLER_TARGET_IMAGES_DIR}/containers/
	    done
	fi

	if [ -n "${HD_MODULES}" ]; then
	    ## Copy the kernel modules tarball to USB drive
	    cp ${HD_MODULES} ${mnt_rootfs}${INSTALLER_TARGET_FILES_DIR}
	    if [ $? -ne 0 ]
	    then
		debugmsg ${DEBUG_CRIT} "ERROR: Failed to copy kernel modules"
		return 1
	    fi
	fi

	# puppet modules etc.
	if [ -v INSTALL_PUPPET_DIR ]; then
	    if [ -d ${INSTALLER_FILES_DIR}/${INSTALL_PUPPET_DIR} ]; then
		debugmsg ${DEBUG_INFO} "Copying Puppet files to install media"
		recursive_mkdir ${mnt_rootfs}${INSTALLER_TARGET_FILES_DIR}/puppet
		cp -r ${INSTALLER_FILES_DIR}/${INSTALL_PUPPET_DIR}/* ${mnt_rootfs}${INSTALLER_TARGET_FILES_DIR}/puppet/
	    else
		debugmsg ${DEBUG_INFO} "INSTALL_PUPPET_DIR set but directory doesn't exist."
	    fi
	fi

	return 0
}

installer_main "$dev"

exit 0
