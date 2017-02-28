#!/bin/bash

#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2 as
#  published by the Free Software Foundation.

#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#  See the GNU General Public License for more details.

BASEDIR=$(dirname $BASH_SOURCE)

: ${CONFIG_FILE="$BASEDIR/config-hd.sh"}
: ${FUNCTIONS_FILE="$BASEDIR/functions.sh"}

## Load configuration file
if ! [ -e $CONFIG_FILE ]; then
	echo "ERROR: Could not find configuration file (${CONFIG_FILE})"
	exit 1
fi

source $CONFIG_FILE

## Load functions file
if ! [ -e $FUNCTIONS_FILE ]; then
	echo "ERROR: Could not find function definitions (${FUNCTIONS_FILE})"
	exit 1
fi

source $FUNCTIONS_FILE

## Set up trap handler

trap_cmd='trap_handler $?'
trap "${trap_cmd}" EXIT

if ! [ -z ${HARDDRIVE_DEVICE} ] && ! [ -z ${HARDDRIVE_MODEL} ]
then
	## Validate hard drive is present
	dev=$(validate_harddrive "$HARDDRIVE_DEVICE" "$HARDDRIVE_MODEL")
	assert $?
	INSTALLER_BANNER=${HARDDRIVE_BANNER}
	INSTALLER_INTRODUCTION=${HARDDRIVE_INTRODUCTION}
else
	debugmsg ${DEBUG_CRIT} "No storage device provided"
	false
	assert $?
fi

if [ -z $dev ]
then
	debugmsg ${DEBUG_CRIT} "ERROR: Failed to detect device"
	false
	assert $?
fi

custom_install_rules()
{
	local mnt_boot="$1"
	local mnt_rootfs="$2"

	## Copy kernel and files to filesystem
	debugmsg ${DEBUG_INFO} "Copying kernel image"
	install_kernel "${INSTALL_KERNEL}" "${mnt_boot}"
	if [ $? -ne 0 ]; then
	    debugmsg ${DEBUG_CRIT} "Failed to copy kernel image"
	    return 1
	fi

	debugmsg ${DEBUG_INFO} "Extracting root filesystem "
	extract_tarball "${INSTALL_ROOTFS}" "${mnt_rootfs}"
	if [ $? -ne 0 ]; then
	    debugmsg ${DEBUG_CRIT} "Failed to copy root filesystem"
	    return 1
	fi
	
	debugmsg ${DEBUG_INFO} "Extracting kernel modules "
	extract_tarball "${INSTALL_MODULES}" "${mnt_rootfs}"
	if [ $? -ne 0 ]; then
	    debugmsg ${DEBUG_CRIT} "Failed to copy kernel modules"
	    return 1
	fi

	return 0
}

installer_main "$dev"

exit 0
