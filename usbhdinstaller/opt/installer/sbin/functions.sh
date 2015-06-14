######################################################################
## Functions
######################################################################

debugmsg()
{
	local msg_level=$1
	shift

	if [ -z $msg_level ]
	then
		echo "debugmsg: No debug level specified with message." >&2
	fi

	if [ -z "$*" ]
	then
		echo "debugmsg: No debug message was given" >&2
	fi

	if [ $msg_level -le $DEBUG_LEVEL ]
	then
		if [ $TRACE -eq 1 ]
		then
			echo "${BASH_SOURCE[1]}:${FUNCNAME[1]}() line ${BASH_LINENO[0]} - $@" >&2
		else
			echo "$@" >&2
		fi
	fi
}

assert()
{
	if [ $1 -ne 0 ]
	then
		trap - EXIT
		command exit 1
	fi
}

assert_return()
{
	if [ $1 -ne 0 ]
	then
		return $1
	fi
}

trap_handler()
{
    if [ $1 -ne 0 ]; then
	debugmsg ${DEBUG_CRIT} "######################################################################"
        debugmsg ${DEBUG_CRIT} "ERROR: An unexpected condition occurred: $1"
	debugmsg ${DEBUG_CRIT} "######################################################################"
    fi
}

exit()
{
    trap - EXIT
    command exit "$@"
}

pidspinner()
{
        local pid1=$1
        local period=$2
        local count=0

	if [ -z $pid1 ]
	then
		return
	fi

        (
        while [ -e /proc/$pid1 ]
        do
                case "$count" in
                0) c='/';  count=1;;
                1) c='-';  count=2;;
                2) c='\\'; count=3;;
                3) c='|';  count=0;;
                esac

                echo -ne "$c"
                sleep $period
                echo -ne "\b"
        done
        )&

        pid2=$!
        wait $pid1

        local rc=$?
        wait $pid2

        return $rc
}

confirm_install()
{
	read -p "Do you wish to continue? [y/n] " -n 1
	echo

	if [[ ! $REPLY =~ ^[Yy]$ ]]
	then
	    debugmsg ${DEBUG_WARN} "Installation cancelled by user"
	    return 1
	fi

	debugmsg ${DEBUG_INFO} -ne "Installation confirmed, beginning in:  "

	for n in 3 2 1
	do
		debugmsg ${DEBUG_INFO} -ne "\b$n"
		sleep 1
	done

	echo -ne "\n"
}

recursive_mkdir()
{
        local dir="$1"

        if ! [ -d ${dir} ]
        then
                recursive_mkdir $(dirname ${dir})
		if [ $? -ne 0 ]
		then
			return $?
		fi

                mkdir ${dir}
		if [ $? -ne 0 ]
		then
			debugmsg ${DEBUG_CRIT} "ERROR: Could not make directory ${dir}"
			return 1
		fi
        fi
	return 0
}


confirm_reboot()
{
	read -p "Do you wish to reboot? [y/n] " -n 1
	echo

	if [[ $REPLY =~ ^[Yy]$ ]]
	then
		debugmsg ${DEBUG_INFO} "Initiating reboot sequence..."

		debugmsg ${DEBUG_INFO} -ne "Rebooting in:  "

		for n in 3 2 1
		do
			debugmsg ${DEBUG_INFO} -en "\b$n"
			sleep 1
		done

		reboot
	fi
}

display_banner()
{
	echo "$INSTALLER_BANNER"
}

display_introduction()
{
	echo "$INSTALLER_INTRODUCTION"

	sleep 2
	confirm_install
	
	return $?
}

display_finalmsg()
{
	echo "$INSTALLER_COMPLETE"
}

verify_prerequisite_files()
{
	local all_files_found=0
	for file in ${PREREQ_FILES}
	do
		if ! [ -e ${file} ]
		then
			debugmsg ${DEBUG_CRIT} "ERROR: Could not find necessary file: ${file}"
			all_files_found=1
		fi
	done

	return $all_files_found
}

# Input parameter is a sysfs block device: eg. /sys/block/sdX
validate_usbstorage()
{
        local usbstorage_device=$1
	local rc=1

        if [ -z ${usbstorage_device} ] || ! [ -e ${usbstorage_device} ]
        then
                debugmsg ${DEBUG_CRIT} "ERROR: Please specify a valid block device"
                return 1
        fi

        local sysfs_path=$(dirname $usbstorage_device)/$(readlink $usbstorage_device)
        local parent=$(dirname ${sysfs_path})
        while true
        do
                if [ "x${parent}" == "x/" ]
                then
                        break
                fi

                if [ -e ${parent}/driver ]
                then
                        local driver_path=$(readlink ${parent}/driver)
                        local driver=$(basename ${driver_path})
			local scsi_device="sd"
                        if [ "x${driver}" != "x${scsi_device}" ]
                        then
                                break
                        fi
                fi
                local parent=$(dirname ${parent})
        done

        if [ "x${driver}" == "xusb-storage" ]
        then
                rc=0
		echo $(basename ${usbstorage_device})
        else
                debugmsg ${DEBUG_CRIT} "ERROR: Specified block device (${usbstorage_device}) is not a usb-storage device."
                rc=1
        fi
        return $rc
}

# Input parameter is a sysfs scsi device: eg. /sys/class/scsi_disk/0:0:0:0/device
validate_harddrive()
{
	local harddrive_device="$1"
	local harddrive_model="$2"

	if [ -z ${harddrive_device} ] || [ -z ${harddrive_model} ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Input parameters not provided"
		return 1
	fi

	# Verify that this is the correct machine.
	if ! [ -e ${harddrive_device} ]; then
	    debugmsg ${DEBUG_CRIT} "ERROR: Could not find (${harddrive_device}) to verify that this machine is a ${BOARD_NAME}."
	    debugmsg ${DEBUG_CRIT} "This hard drive installer is designed for the ${board_Name} and may not"
	    debugmsg ${DEBUG_CRIT} "function properly on other boards."
	    return 1
	fi
	
	local model=$(cat ${harddrive_device}/model)
	if [ "x${model}" != "x${harddrive_model}" ]; then
	    debugmsg ${DEBUG_CRIT} "ERROR: Could not confirm that the hard drive model"
	    debugmsg ${DEBUG_CRIT} "Expected ${harddrive_model} but discovered ${model}."
	    return 1
	fi
	
	
	# Discover block device name associated with internal hard drive
	echo $(ls -d ${harddrive_device}/block* | sed "s|${harddrive_device}/block:||")
	return 0
}

remove_partitions()
{
	local device="$1"

	if [ -z $device ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Input parameters not provided"
	fi

	debugmsg ${DEBUG_INFO} "Removing all partitions"

	local count=0
	local attempts=3

	while partitions=$(/sbin/parted -s /dev/${device} print | grep '^ *[0-9]')
	do
		for i in $(echo $partitions | awk '{print $1}')
		do
			debugmsg ${DEBUG_INFO}  "Removing partition $i on /dev/${device}"
			/sbin/parted -s /dev/${device} "rm $i"
		done
	
		if [ $count -gt $attempts ]; then
			debugmsg ${DEBUG_CRIT} "ERROR: Could not remove partitions from internal hard drive after $attempts attempts"
			return 1
		else
			(( count++ ))
		fi
	done

	return 0
}

create_partition()
{
	local device=$(basename $1)
	local partnum="$2"
	local fstype="$3"
	local part_start="$4"
	local part_end="$5"

	if [ -z $device ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Input parameters not provided"
	fi


# XXX: TODO: use parted to mklabel msdos on the device (if NBD)	
	debugmsg ${DEBUG_INFO} "Creating partition ${device}${partnum}"
# XXX
	# echo /sbin/parted -s /dev/${device} "mkpart primary ${fstype} ${part_start} ${part_end}"
	/sbin/parted -s /dev/${device} "mkpart primary ${fstype} ${part_start} ${part_end}" > /dev/null 2>&1
	
	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Failed to create partition on /dev/${device}${partnum}"
		return 1
	fi

# XXX
	while !([ -e /dev/${device}${partnum} ] || [ -e /dev/${device}p${partnum} ])
	do
		sleep 1
	done
	
	return 0
}

create_filesystem()
{
	local partition="$1"
	local filesystem="$2"
	local label="$3"
	local makefs

	if [ -z $partition ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Input parameters not provided"
		return 1
	fi

	if ! [ -e /dev/${partition} ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Specified partition (${partition}) does not exist"
		return 1
	fi

	debugmsg ${DEBUG_INFO} "Creating ${filesystem} filesystem on ${partition}"
	if [ "x${filesystem}" == "xext2" ]
	then
		makefs="mkfs.ext2 -L ${label}"
	elif [ "x${filesystem}" == "xext3" ]
	then
		makefs="mkfs.ext3 -L ${label}"
	elif [ "x${filesystem}" == "xfat16" ]
	then
		makefs="mkfs.msdos -F 16 -n ${label}"
	elif [ "x${filesystem}" == "xfat32" ]
	then
		makefs="mkfs.msdos -F 32 -n ${label}"
	else
		debugmsg ${DEBUG_CRIT} "ERROR: Could not determine filesystem type"
		return 1
	fi
	${makefs} /dev/${partition} > /dev/null 2>&1 &
	pidspinner "$!" "1"
	
	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Failed to create new filesystem on ${partition}"
		return 1
	fi
}

label_filesystem()
{
	local partition=$(basename $1)
	local filesystem="$2"
	local label="$3"

	debugmsg ${DEBUG_INFO} "Applying label ${label} to ${partition}"

	if [ "x${filesystem}" == "xext2" ] || [ "x${filesystem}" == "xext3" ]
	then
		e2label "/dev/${partition}" "${label}"
	elif [ "x${filesystem}" == "xfat16" ] || [ "x${filesystem}" == "xfat32" ]
	then
		mlabel -i "/dev/${partition}" "::${label}"
	else
		debugmsg ${DEBUG_CRIT} "ERROR: Could not determine filesystem type"
		return 1
	fi
	return 0
}

tmp_mount()
{
	local partition=/dev/$(basename $1)

	if ! [ -e ${partition} ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Device (${partition}) does not exist"
		return 1
	fi

	## Create temporary mount points
	local mountpoint=$(mktemp -d)

	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Could not create temporary directory"
		return 1
	fi
	

	mount -o noatime ${partition} ${mountpoint}
	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Failed to mount new filesystem on ${partition} on ${mountpoint}"
		return 1
	fi

	echo ${mountpoint}
	return 0
}

umount_partitions()
{
	local device=$1
	local count=0
	local attempts=3

	if [ -z $device ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Input parameters not provided"
	fi

	while mounts=$(cat /proc/mounts | grep ${device})
	do
		for i in $(echo $mounts | awk '{print $2}')
		do
			debugmsg ${DEBUG_INFO} "Unmounting $i"
			umount $i
		done

		if [ $count -ge $attempts ]; then
			debugmsg ${DEBUG_CRIT} "ERROR: Could not unmount partitions from internal hard drive after $attempts attempts"
			return 1
		else
			(( count++ ))
		fi
	done

	return 0
}

install_grub()
{
	local device="$1"
	local mountpoint="$2"

	# if we are installing to a nbd device, assume that we are working in
	# a virtual environment, and use "vda" as the boot device
	echo ${device} | grep -q nbd
	if [ $? -eq 0 ]; then
	    p2="vda2"
	else
	    p2="${device}2"
	fi

	debugmsg ${DEBUG_INFO} "Installing the GRUB bootloader"

	${CMD_GRUB_INSTALL} --root-directory=${mountpoint} --no-floppy --recheck /dev/${device} # > /dev/null 2>&1
	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Installation of grub failed on /dev/${dev}"
		return 1
	fi

	cp ${INSTALL_GRUBCFG} ${mountpoint}/boot/grub/grub.cfg
	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Could not copy grub configuration file to ${mountpoint}/boot/grub/"
		return 1
	fi

	if [ -n "${INSTALL_KERNEL}" ]; then
		local kernel_name=`basename ${INSTALL_KERNEL}`
		local initramfs_name=`basename ${INSTALL_INITRAMFS}`
		sed "s|%INSTALL_KERNEL%|${kernel_name}|" -i ${mountpoint}/boot/grub/grub.cfg
		sed "s|%INSTALL_INITRAMFS%|${initramfs_name}|" -i ${mountpoint}/boot/grub/grub.cfg
		sed "s|%INSTALLER_PARTITION%|${p2}|" -i ${mountpoint}/boot/grub/grub.cfg
	else
		debugmsg ${DEBUG_CRIT} "ERROR: Could not update grub configuration with install kernel"
		return 1
	fi
	    
	return 0
}

install_kernel()
{
	local kernel_src="$1"
	local boot_part="$2"
	local initramfs="$3"
	local initramfs_dest="$4"

	debugmsg ${DEBUG_INFO} "Installing new kernel image to boot partition"

	mkdir -p ${boot_part}/images
	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Failed to create images directory on boot partition"
		return 1
	fi

	cp ${kernel_src} ${boot_part}/images/
	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Failed to copy kernel image to boot partition"
		return 1
	fi

	if [ -n "${initramfs}" ]; then
		cp ${initramfs} ${boot_part}/images/${initramfs_dest}
		if [ $? -ne 0 ]
		then
			debugmsg ${DEBUG_CRIT} "ERROR: Failed to copy initramfs image to boot partition"
			return 1
		fi
	fi

	return 0
}

extract_tarball()
{
	local tarball_src="$1"
	local destination="$2"

	# tar -jxf ${tarball_src} -C ${destination} > /dev/null 2>&1 &
	tar -jxf ${tarball_src} -C ${destination} &
	pidspinner "$!" "1"

	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Failed to extract tarball ${tarball_src} to ${destination}"
		return 1
	fi

	return 0
}

installer_main()
{
	local device="$1"

	if [ -z $device ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Could not determine destination device"
	fi

	## Display installer banner
	display_banner
	
	## Verify that installation files exist
	verify_prerequisite_files
	assert $?

	declare -f install_summary > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
            install_summary
        fi
		
	## Display Installer Introduction
	display_introduction
	assert $?
	
	## Unmount any partitions on device
	umount_partitions "$dev"
	assert $?
	
	## Remove all existing partitions
	remove_partitions "$dev"
	assert $?
	
	## Create new partitions
	debugmsg ${DEBUG_INFO} "Creating new partitions"
	create_partition "${dev}" 1 ${BOOTPART_FSTYPE} ${BOOTPART_START} ${BOOTPART_END}
	assert $?
	create_partition "${dev}" 2 ${ROOTFS_FSTYPE} ${ROOTFS_START} ${ROOTFS_END}
	assert $?

	local p1
	local p2
	# XXX: TODO. the partition name should be returned by create_partition
	if [ -e /dev/${dev}1 ]; then
	    p1="${dev}1"
	    p2="${dev}2"
	fi
	if [ -e /dev/${dev}p1 ]; then
	    p1="${dev}p1"
	    p2="${dev}p2"
	fi
	
	## Create new filesystems
	debugmsg ${DEBUG_INFO} "Creating new filesystems "
	create_filesystem "${p1}" "${BOOTPART_FSTYPE}" "${BOOTPART_LABEL}"
	assert $?

	create_filesystem "${p2}" "${ROOTFS_FSTYPE}" "${ROOTFS_LABEL}"
	assert $?

	## Create temporary mount points
	mnt1=$(tmp_mount "${p1}")
	assert $?
	
	mnt2=$(tmp_mount "${p2}")
	assert $?
	
	## Install Bootloader
	install_grub "${dev}" "${mnt1}"
	assert $?

	declare -f custom_install_rules > /dev/null 2>&1

	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_INFO} "ERROR: Could not determine how to install files"
		false
		assert $?
	else
		custom_install_rules "${mnt1}" "${mnt2}"
		assert $?
	fi
	
	# Cleanup
	debugmsg ${DEBUG_INFO} "Unmounting all partitions"
	umount ${mnt1}
	umount ${mnt2}
	
	# Finish Installation
	display_finalmsg
	
	# Confirm reboot
	if [ ${CONFIRM_REBOOT} -eq 1 ]
	then 
		confirm_reboot
	fi
}
