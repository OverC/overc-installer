
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2 as
#  published by the Free Software Foundation.

#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#  See the GNU General Public License for more details.

# arg1: name of function to override
# arg2: new name of function (still callable). If not passed $1_old is used
override_function()
{
    orig=$1
    save_name=$2
    if [ -z "$save_name" ]; then
	save_name=$1_old
    fi

    local ORIG_FUNC=$(declare -f $orig)
    if [ -n "${ORIG_FUNC}" ]; then
	local NEWNAME_FUNC="$save_name${ORIG_FUNC#$orig}"
	eval "$NEWNAME_FUNC"
    fi
}


######################################################################
## Functions
######################################################################

debugmsg()
{
	local msg_level=$1
	shift

	if [ -z "$msg_level" ]
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
	case $1 in
		SIGINT)
			debugmsg ${DEBUG_INFO} "Installation cancelled by user."
			;;
		EXIT)
			if [ $2 -ne 0 ]; then
				debugmsg ${DEBUG_CRIT} "######################################################################"
				debugmsg ${DEBUG_CRIT} "ERROR: An unexpected condition occurred: $1"
				debugmsg ${DEBUG_CRIT} "######################################################################"
			fi
			;;
		*)
			;;
	esac

	# Clean up temporary things
	clean_up

	exit 0
}

trap_with_name() {
	func="$1"
	shift
	for sig; do
		trap "$func $sig $?" "$sig"
	done
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

	if [ ! -v CONFIRM_INSTALL ] || [ ${CONFIRM_INSTALL} -eq 1 ]; then
		sleep 2
		confirm_install
		return $?
	fi
	
	return 0
}

display_finalmsg()
{
	echo "$INSTALLER_COMPLETE"
}


verify_utility()
{
    local utility_name=$1

    # type is faster than 'which' and is a builtin
    type ${utility_name} >/dev/null 2>&1
    return $?
}

verify_root_user()
{
    if [ "$EUID" -ne 0 ]; then
	return 1
    fi
    return 0
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

        if [ -z ${usbstorage_device} ] || ! [ -e ${usbstorage_device} ]; then
                debugmsg ${DEBUG_CRIT} "ERROR: Please specify a valid block device"
                return 1
        fi

        local sysfs_path=$(dirname $usbstorage_device)/$(readlink $usbstorage_device)
        local parent=$(dirname ${sysfs_path})

	echo $parent | grep -q virtual
	if [ $? -eq 0 ]; then
	    # this is a virtual block device, return ok
	    return 0
	fi

        while true; do
                if [ "x${parent}" == "x/" ]; then
                        break
                fi

                if [ -e ${parent}/driver ]; then
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

        if [ "x${driver}" == "xusb-storage" ]; then
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
		debugmsg ${DEBUG_CRIT} "ERROR: validate_harddrive input parameters not provided"
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
		debugmsg ${DEBUG_CRIT} "ERROR: remove_partitions input parameters not provided"
	fi

	debugmsg ${DEBUG_INFO} "Removing all partitions"

	local count=0
	local attempts=3

	while partitions=$(/sbin/parted -s /dev/${device} print 2>/dev/null | grep '^ *[0-9]')
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
		debugmsg ${DEBUG_CRIT} "ERROR: create_partition input parameters not provided"
	fi

	debugmsg ${DEBUG_INFO} "Creating partition ${device}${partnum}"
	# use parted to mklabel msdos if no partition table yet exists on the device
	unknown_part_table=$(parted /dev/${device} print 2>/dev/null | grep 'Partition Table' | grep -c unknown)
	if [ $unknown_part_table -eq 1 ]; then
	    /sbin/parted -s /dev/${device} "mklabel msdos" > /dev/null 2>&1
	fi
	/sbin/parted -s /dev/${device} "mkpart primary ${fstype} ${part_start} ${part_end}" > /dev/null 2>&1
	
	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Failed to create partition on /dev/${device}${partnum}"
		return 1
	fi

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
		debugmsg ${DEBUG_CRIT} "ERROR: create_filesystem input parameters not provided"
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
	elif [ "x${filesystem}" == "xext4" ]
	then
		makefs="mkfs.ext4 -L ${label}"
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
		debugmsg ${DEBUG_CRIT} "ERROR: umount_partitions input parameters not provided"
	fi

	sync
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

install_dtb()
{
	local mountpoint="$1"
	local dtb="$2"
	## Copy the dtb file
	if [ -e "$dtb" ]; then
		debugmsg ${DEBUG_CRIT} "INFO: found dtb "
		cp $dtb ${mountpoint}/dtb
	else
		debugmsg ${DEBUG_CRIT} "ERROR: cannot find dtb file $dtb"
		return 1
	fi
}

install_bootloader()
{
    echo "install_bootloader: default function, add implementation via: override_function"
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

	debugmsg ${DEBUG_INFO} "Checking GRUB consistency"

	GRUB_VER=$( ${CMD_GRUB_INSTALL} --version | awk -F '.'  '{ print $1}' | awk -F ' ' '{print $NF}' )
	# See if our grub config is a legacy menu.lst file
	echo ${INSTALL_GRUBCFG} | grep -q menu
	MENU_GRUB_CFG=$?
	if [ ${MENU_GRUB_CFG} -ne 0 ] && [ ${GRUB_VER} == "0" ]; then
		debugmsg ${DEBUG_CRIT} "ERROR: GRUB version is legacy but cfg file is not menu.lst style"
		return 1
	fi
	if [ ${MENU_GRUB_CFG} -eq 0 ] && [ ${GRUB_VER} != "0" ]; then
		debugmsg ${DEBUG_CRIT} "ERROR: GRUB config file is menu.lst style but GRUB version is 2"
		return 1
	fi

	debugmsg ${DEBUG_INFO} "Installing the GRUB bootloader"

	# --recheck doesn't function with loopback and nbd devices for grub legacy, write our own device.map
	# additionally we have to use the 'grub name' with these devices or grub-install will fail
	if [ ${GRUB_VER} == "0" ] && ( [[ ${device} = *nbd* ]] || [[ ${device} = *loop* ]] ); then
	    mkdir -p ${mountpoint}/boot/grub
	    echo "(hd0) /dev/${device}" > ${mountpoint}/boot/grub/device.map
	    ${CMD_GRUB_INSTALL} --root-directory=${mountpoint} --no-floppy hd0 # > /dev/null 2>&1
	else
	    ${CMD_GRUB_INSTALL} --root-directory=${mountpoint} --no-floppy --recheck /dev/${device} # > /dev/null 2>&1
	fi
	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Installation of grub failed on /dev/${dev}"
		return 1
	fi

	if [ ${MENU_GRUB_CFG} -ne 0 ]; then
		GRUB_CFG_NAME="grub.cfg"
	else
		GRUB_CFG_NAME="menu.lst"
	fi

	cp ${INSTALL_GRUBCFG} ${mountpoint}/boot/grub/${GRUB_CFG_NAME}
	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Could not copy grub configuration file to ${mountpoint}/boot/grub/"
		return 1
	fi

	if [ -n "${INSTALL_KERNEL}" ]; then
		local kernel_name=`basename ${INSTALL_KERNEL}`
		local initramfs_name=`basename ${INSTALL_INITRAMFS}`
		sed "s|%INSTALL_KERNEL%|${kernel_name}|" -i ${mountpoint}/boot/grub/${GRUB_CFG_NAME}
		sed "s|%INSTALL_INITRAMFS%|${initramfs_name}|" -i ${mountpoint}/boot/grub/${GRUB_CFG_NAME}
		sed "s|%INSTALLER_PARTITION%|${p2}|" -i ${mountpoint}/boot/grub/${GRUB_CFG_NAME}
		sed "s|%ROOTFS_LABEL%|${ROOTFS_LABEL}|" -i ${mountpoint}/boot/grub/${GRUB_CFG_NAME}
		if ! [ -n "$DISTRIBUTION" ]; then
			DISTRIBUTION="OverC"
		fi
		sed "s|%DISTRIBUTION%|${DISTRIBUTION}|" -i ${mountpoint}/boot/grub/${GRUB_CFG_NAME}
	else
		debugmsg ${DEBUG_CRIT} "ERROR: Could not update grub configuration with install kernel"
		return 1
	fi
	
	#install efi boot

	if [ -n "${INSTALL_EFIBOOT}" ] && [ -e "${INSTALL_EFIBOOT}" ]; then
		debugmsg ${DEBUG_INFO} "Installing the EFI bootloader"
		mkdir -p ${mountpoint}/EFI/BOOT/
		cp $INSTALL_EFIBOOT ${mountpoint}/EFI/BOOT/
		cp ${mountpoint}/boot/grub/${GRUB_CFG_NAME} ${mountpoint}/EFI/BOOT/
		echo `basename $INSTALL_EFIBOOT` >${mountpoint}/startup.nsh
	else
		cp ${BASEDIR}/startup.nsh ${mountpoint}/
		sed -i "s/%ROOTLABEL%/${ROOTFS_LABEL}/" ${mountpoint}/startup.nsh
		sed -i "s/%INITRD%/\/images\/${initramfs_name}/" ${mountpoint}/startup.nsh
		sed -i "s/%BZIMAGE%/\\\images\\\bzImage/" ${mountpoint}/startup.nsh
	fi
	chmod +x ${mountpoint}/startup.nsh

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

function extract_container_name
{
    # Params: $1 = filename
    #
    # Container file names typically look like:
    # a-b-c-...-z-some-arch.tar.bz
    # where z is typically dom{0,1,e,E} etc.
    # We want to pull z out of the file name and use
    # it for the container name.
    # There has to be at least a dom0 container, so we
    # look for it and use it as a template for extracting
    # z out of the filename.
    local disposable_suffix
    local dom0_name
    local z_part

    # Use dom0 as the template for discovering the
    # disposable suffix eg. -some-arch.tar.bz
    dom0_name=$( ls $CONTAINERSDIR/*-dom0-* )
    if [ -z "$dom0_name" ]; then
        echo "ERROR: cannot find the dom0 container image"
        exit 1
    fi
    # Anything after dom0 in the filename is considered to be the suffix
    disposable_suffix=$( echo $dom0_name | awk 'BEGIN { FS="dom0"; } { print $NF; }' )
    # Strip away the suffix first, then anything after the last '-' is the container name
    z_part=$( echo ${1%$disposable_suffix} | awk 'BEGIN { FS="-"; } { print $NF; }' )
    echo ${z_part}
}

install_container()
{
    target_dir=$1
    chroot . /bin/bash -c "/tmp/overc-cctl add -d -a -g onboot -t 0 -n $cname -f /tmp/$c ${ttyconsole_opt}"
}


# $1: array
# $2: new name
ref_array() {
    local varname="$1"
    local export_as="$2"
    local code=$(declare -p "$varname")
    echo ${code/$varname/-g $export_as}
}

# $1: map
keys() {
    eval $(ref_array "$1" array)
    local key

    for key in "${!array[@]}"; do
	echo $key
        #printf "Key: %s, value: %s\n" "$key" "${array[$key]}"
    done
}

# $1: map
# $2: key
value() {
    eval $(ref_array "$1" array)
    local key
    local match=$2

    for key in "${!array[@]}"; do
	if [ "$key" = "$match" ]; then
	    echo ${array[$key]}
	fi
    done
}

# $1: the property map variable to fill (must already be declared)
# $2: a variable with a list of items:<properties>
# output: a property map in $2
create_property_map()
{
    local ret_property_map_name="$1"
    shift
    local input_var=$@

    # containers are listed in HDINSTALL_CONTAINERS as:
    #    <full path>/<container tgz>:<properties>
    values_to_check=${input_var}
    declare -A temp_property_map=()
    for c in ${values_to_check}; do
	props=""

	cn=`echo "${c}" | cut -d':' -f1`
	cn_short=`basename ${cn}`
	cname=`${SBINDIR}/cubename $CNAME_PREFIX $cn_short`

	all_props=""
	#by now 20 properties is enough
	for prop_count in {1..20}; do
	    props=`echo "${c}" | cut -d':' -f$prop_count`
	    if [ "${cn}" == "${props}" ]; then
		props=""
	    else
		all_props="$all_props $props"
	    fi
	done

	# store any properies as: <short name> <value> in the properties array
	temp_property_map[$cname]="${all_props}"
	eval $ret_property_map_name[$cname]="\"${all_props}\""
    done
}

strip_properties()
{
    local input_var=$@

    # containers are listed in HDINSTALL_CONTAINERS as:
    #    <full path>/<container tgz>:<properties>
    extracted_var=""
    for c in ${input_var}; do
	cn=`echo "${c}" | cut -d':' -f1`
	# this gets us the name without any :<properties>
	extracted_var="${extracted_var} ${cn}"
    done

    echo $extracted_var
}

# arg1: service name
# arg2: container name
service_install()
{
    local service="$1"
    local cname="$2"
    local sname

    if [ ! -f "${BASEDIR}/../files/${service}" ]; then
	if [ ! -f "${service}" ]; then
	    debugmsg ${DEBUG_INFO} "ERROR: Could not locate service ${service}"
	    false
	    assert $?
	fi
    else
	service="${BASEDIR}/../files/${service}"
    fi
    sname=`basename ${service}`

    if [ -d "${LXCBASE}/${cname}/rootfs/usr/lib/systemd/system/" ]; then
	tgt="${LXCBASE}/${cname}/rootfs/usr/lib/systemd/system/"
    else
	if [ -d "${LXCBASE}/${cname}/rootfs/usr_temp" ]; then
	    tgt="${LXCBASE}/${cname}/rootfs/usr_temp/lib/systemd/system"
	fi
    fi

    if [ -n "${tgt}" ]; then
	mkdir -p ${tgt}
	# copy service
	cp -f "${service}" ${tgt}/${sname}
	# activate service
	ln -s /usr/lib/systemd/system/${sname} ${LXCBASE}/${cname}/rootfs/etc/systemd/system/multi-user.target.wants/${sname}
	echo "[INFO] ${cname}: Service ${sname} installed and activated"
    else
	echo "[WARNING] ${cname}: could not enable service ${sname}, target directory not found"
    fi
}
# arg1: replacement target
# arg2: replacement string
service_modify()
{
    local rtarget="$1"
    local rstring="$2"
    local cname="$3"
    local sname="$4"

    if [ -d "${LXCBASE}/${cname}/rootfs/usr/lib/systemd/system/" ]; then
	tgt="${LXCBASE}/${cname}/rootfs/usr/lib/systemd/system/"
    else
	if [ -d "${LXCBASE}/${cname}/rootfs/usr_temp" ]; then
	    tgt="${LXCBASE}/${cname}/rootfs/usr_temp/lib/systemd/system"
	fi
    fi

    if [ -n "${tgt}" ]; then
	# replace
	eval sed -i -e "s,${rtarget},${rstring}," ${tgt}/${sname}
    else
	echo "[WARNING] ${cname} could not modify service ${sname}, target directory not found"
    fi
}

# arg1: services name, could be globs
# arg2: container name (optional)
service_disable()
{
    local services="$1"
    local cname="$2"
    local slinks

    services="${services%.service}.service"
    local debug_msg="[INFO]: Can not find the service ${services} to disable"

    if [ -z "${cname}" ]; then
        # For essential
        slinks=`find ${TMPMNT}/etc/systemd/ -name ${services} 2>/dev/null`
        debug_msg="${debug_msg} for essential."
    else
        # For containers
        slinks=`find ${LXCBASE}/${cname}/rootfs/etc/systemd/ -name ${services} 2>/dev/null`
        debug_msg="${debug_msg} for ${cname}."
    fi

    if [ -z "${slinks}" ]; then
        debugmsg ${DEBUG_INFO} ${debug_msg}
        return 1
    fi

    rm -f ${slinks}
    return 0
}

# ConditionVirtualization=!container is added in the service file
# so it will check whether the system is executed in a container
#
# arg1: services name, could be globs
# arg2: container name
service_add_condition_for_container()
{
    local services="$1"
    local cname="$2"
 
    services="${services%.service}.service"
    local spaths=`find ${LXCBASE}/${cname}/rootfs/lib/systemd/ \
                       ${LXCBASE}/${cname}/rootfs/usr/lib/systemd/ \
                       -name ${services} 2>/dev/null`

    if [ -z "${spaths}" ]; then
        debugmsg ${DEBUG_INFO} "[INFO]: Can not find the service ${services} in ${cname}."
        return 1
    fi

    for p in ${spaths}; do
        sed -i -e '/Description/ a\ConditionVirtualization=!container' ${spaths}
    done
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

clean_up()
{
	# Cleanup
	debugmsg ${DEBUG_INFO} "Cleaning up..."
	sync
	[ -n "${mnt1}" ] && umount ${mnt1}
	[ -n "${mnt2}" ] && umount ${mnt2}
	rm $tmpfile
}

#TODO: value sanity check
interactive_partition()
{
	# define if this is an installer image
	# If this is an installer image, we provide only two partitions for user to choose.
	# If this is an live/harddrive image, we provide four partitions for user to configure.
	local install_type="$1"

	local size="$2"
	local localconf_dir="$3"
	local lastsize=0
	local localconf="${localconf_dir}/config.sh"
	local localpartitionlayout="${localconf_dir}/fdisk-4-partition-user-layout.txt"
	if [ -z "$tmpfile" ]; then
		tmpfile=$(mktemp)
	fi

	local prompt="Destinition device will be partitioned using the following schema: \n"
	if [ "$install_type" == "installer" ]; then
		lastsize=`numfmt --to=iec --round=down $(expr $size - 268435456)`
		prompt="$prompt 1) boot (256M) \n 2) root ($lastsize)"
	else
		lastsize=`numfmt --to=iec --round=down $(expr $size - 3221225472)`
		prompt="$prompt 1) boot (256M) \n 2) swap (768M) \n 3) root (2G) \n 4) containers ($lastsize)"
	fi
	dialog --yesno "$prompt" 10 80
	local dialog_res=$?
	if [ $dialog_res -eq 0 ]; then
		# User answered yes. Just use default
		if [ "$install_type" == "installer" ]; then
			bootpartsize="256M"
			rootfspartsize="-1"
		else
			bootpartsize="256M"
			swappartsize="768M"
			rootfspartsize="2048M"
			containerpartsize=`numfmt --to=iec --round=down $(expr $size - 3221225472)`
		fi
	else
		# User answered no. Prompt for sizes.
		# TODO: let user do manual partition layout
		if [ "$install_type" == "installer" ]; then
			dialog --no-cancel --inputbox "Boot partition size:" 8 40 "256M" 2>$tmpfile
			bootpartsize=`numfmt --from=auto $(cat $tmpfile)`
			lastsize=`numfmt --to=iec $(expr $size - ${bootpartsize})`
			dialog --no-cancel --inputbox "Rootfs partition size:" 8 40 "${lastsize}" 2>$tmpfile
			rootfspartsize=$(cat $tmpfile)
		else
			dialog --no-cancel --inputbox "Boot partition size:" 8 40 "256M" 2>$tmpfile
			bootpartsize=`numfmt --from=auto $(cat $tmpfile)`
			dialog --no-cancel --inputbox "Swap partition size:" 8 40 "768M" 2>$tmpfile
			swappartsize=`numfmt --from=auto $(cat $tmpfile)`
			dialog --no-cancel --inputbox "Rootfs partition size:" 8 40 "2G" 2>$tmpfile
			rootfspartsize=`numfmt --from=auto $(cat $tmpfile)`
			dialog --no-cancel --inputbox "Containers partition size:" 8 40 \
				"`numfmt --to=iec --round=down $(expr $size - ${bootpartsize} - ${swappartsize} - ${rootfspartsize})`" 2>$tmpfile
			containerpartsize=`numfmt --from=auto $(cat $tmpfile)`
		fi
	fi
	if [ "$install_type" == "installer" ]; then
		echo "BOOTPART_START=\"0\"" >> ${localconf}
		echo "BOOTPART_END=\"${bootpartsize}\"" >> ${localconf}
		echo "BOOTPART_FSTYPE=\"fat32\"" >> ${localconf}
		echo "BOOTPART_LABEL=\"OVERCBOOT\"" >> ${localconf}
		echo "ROOTFS_START=\"${bootpartsize}\"" >> ${localconf}
		if [ ${rootfspartsize} == "-1" ]; then
			echo "ROOTFS_END=\"${rootfspartsize}\"" >> ${localconf}
		else
			echo "ROOTFS_END=\"$(expr `numfmt --from=auto $bootpartsize` + `numfmt --from=auto $rootfspartsize`)\"" >> ${localconf}
		fi
		echo "ROOTFS_FSTYPE=\"ext2\"" >> ${localconf}
		echo "ROOTFS_LABEL=\"OVERCINSTROOTFS\"" >> ${localconf}
	else
		cat <<EOF > ${localpartitionlayout}
d
1
d
2
d
3
d
4


n
p
1

+`numfmt --to=iec --from=iec ${bootpartsize}`
n
p
2

+`numfmt --to=iec --from=iec ${swappartsize}`
n
p
3

+`numfmt --to=iec --from=iec ${rootfspartsize}`
n
p

+`numfmt --to=iec --from=iec ${containerpartsize}`
a
1
t
1
b
t
2
82
t
3
83
w
p
q


EOF
		echo "FDISK_PARTITION_LAYOUT=\"${localpartitionlayout}\"" >> ${localconf}
	fi
}

interactive_config()
{
	local device="$1"
	local localconf_dir="$2"

	if [ -z ${device} ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR in interactive_config: device parameter not provided"
		return 1
	fi

	if [ -z ${localconf_dir} ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR in interactive_config: tmp config directory parameter not provided"
		return 1
	fi

	local localconf="${localconf_dir}/config.sh"
	tmpfile=$(mktemp)

	echo "" > ${localconf}

	# Distribution
	dialog --no-cancel --inputbox "Distribution name:" 8 40 "OverC" 2>$tmpfile
	local dialog_res=$(cat $tmpfile)
	if [ -n "${dialog_res}" ]; then
		echo "DISTRIBUTION=\"${dialog_res}\"" >> ${localconf}
	else
		echo "DISTRIBUTION=\"OverC\"" >> ${localconf}
	fi

	# Container selection
	local filecount=0
	local filelist="" menuitems=""
	if [ -z "$ARTIFACTS_DIR" ]; then
		if [ -e "tmp/deploy/images" ]; then
			filecount=`ls tmp/deploy/images/ -1 | wc -l`
			case "$filecount" in
				0)
					debugmsg ${DEBUG_CRIT}  "Project build incomplete. Please try finish the build first."
					return 1
					;;
				1)
					ARTIFACTS_DIR="`pwd`/tmp/deploy/images/`ls tmp/deploy/images/`"
					;;
				*)
					filelist=`ls tmp/deploy/images` menuitems=""
					for i in $filelist; do
						menuitems="$menuitems $i $i "
					done
					dialog --no-cancel --menu "Found multiple machine target in your project, Please choose one:" \
						$(expr $filecount + 7) 30 $filecount $menuitems 2>$tmpfile
					ARTIFACTS_DIR="`pwd`/tmp/deploy/images/$(cat $tmpfile)"
					;;
			esac
		elif [ -e "images" ]; then
			ARTIFACTS_DIR="`pwd`/images"
		else
			# default to current dir
			ARTIFACTS_DIR="`pwd`"
		fi
	fi
	echo "ARTIFACTS_DIR=\"${ARTIFACTS_DIR}\"" >> ${localconf}
	filecount=`ls $ARTIFACTS_DIR -1 | grep -v menifest | wc -l`
	if [ $filecount -lt 3 ]; then
		debugmsg ${DEBUG_CRIT} "Artifacts are not sufficient. Please verify."
		return 1
	fi

	# exclude manifest files
	filelist=`ls $ARTIFACTS_DIR | grep -v manifest` menuitems=""
	local checklistmenu=""
	for i in $filelist; do
		menuitems="$menuitems $i $i "
		checklistmenu="$checklistmenu $i $i off "
	done

	# Kernel selection
	dialog --no-tags --menu "Please choose kernel:" \
		$(expr $filecount + 7) 100 $filecount $menuitems 2>$tmpfile
	dialog_res=$(cat $tmpfile)
	if [ -z "${dialog_res}" ]; then
		debugmsg ${DEBUG_CRIT} "Kernel not specified. Please try again."
		return 1
	fi
	echo "INSTALL_KERNEL=\"\${ARTIFACTS_DIR}/${dialog_res}\"" >> ${localconf}

	# Rootfs selection
	dialog --no-tags --menu "Please choose rootfs:" \
		$(expr $filecount + 7) 100 $filecount $menuitems 2>$tmpfile
	dialog_res=$(cat $tmpfile)
	if [ -z "${dialog_res}" ]; then
		debugmsg ${DEBUG_CRIT} "Rootfs not specified. Please try again."
		return 1
	fi
	echo "INSTALL_ROOTFS=\"\${ARTIFACTS_DIR}/${dialog_res}\"" >> ${localconf}
	echo "HDINSTALL_ROOTFS=\"\${ARTIFACTS_DIR}/${dialog_res}\"" >> ${localconf}

	# Initramfs selection
	dialog --no-tags --menu "Please choose initramfs:" \
		$(expr $filecount + 7) 100 $filecount $menuitems 2>$tmpfile
	dialog_res=$(cat $tmpfile)
	if [ -z "${dialog_res}" ]; then
		debugmsg ${DEBUG_CRIT} "Initramfs not specified. Please try again."
		return 1
	fi
	echo "INSTALL_INITRAMFS=\"\${ARTIFACTS_DIR}/${dialog_res}\"" >> ${localconf}

	# containers selection
	if [ -d "$ARTIFACTS_DIR/containers" ]; then
		filelist=`ls $ARTIFACTS_DIR/containers` checklistmenu="" filecount=0
		for i in $filelist; do
			let filecount++
			checklistmenu="$checklistmenu $i $i off "
		done
	fi
	dialog --no-tags --checklist "Please choose install containers:" \
		$(expr $filecount + 7) 100 $filecount $checklistmenu 2>$tmpfile
	dialog_res=$(cat $tmpfile)
	if [ -z "${dialog_res}" ]; then
		debugmsg ${DEBUG_CRIT} "Containers not specified. Please try again."
		return 1
	fi

	local hdcontainers=${dialog_res} fmtcontainers=""

	# VT and network prime selection
	menuitems=""
	filecount=0
	for i in ${hdcontainers}; do
		if [ -d "$ARTIFACTS_DIR/containers" ]; then
			fmtcontainers="$fmtcontainers containers/$i"
		else
			fmtcontainers="$fmtcontainers $i"
		fi
		menuitems="$menuitems $i $i "
		dialog --yesno "Do you want to allocate a virtual console for $i?" 10 100
		if [ $? -eq 0 ]; then
			fmtcontainers="$fmtcontainers:console"
			dialog --inputbox "Which virtual terminal to be allocated to $i:" 8 100 2>$tmpfile
			dialog_res=$(cat $tmpfile)

			# TODO: sanity check
			if [ -n "${dialog_res}" ]; then
				fmtcontainers="$fmtcontainers:vty=${dialog_res}"
			fi
		fi
		let filecount++
	done
	dialog --no-tags --menu "Please choose the network prime container:" \
		$(expr $filecount + 7) 100 $filecount $menuitems 2>$tmpfile
	local network_prime_container=$(cat $tmpfile)
	if [ -z "${network_prime_container}" ]; then
		debugmsg ${DEBUG_INFO} "Network prime containers not specified."
	else
		# Define network device
		dialog --inputbox "Please provide the network device to be used in the network prime container:" 8 100 "all" 2>$tmpfile
		dialog_res=$(cat $tmpfile)
		if [ -n "$dialog_res" ]; then
			echo "NETWORK_DEVICE=\"${dialog_res}\"" >> ${localconf}
		fi
	fi

	# Format HDINSTALL_CONTAINERS configuration
	echo "HDINSTALL_CONTAINERS=\" \\" >> ${localconf}
	for i in ${fmtcontainers}; do
		echo -n " \${ARTIFACTS_DIR}/${i}" >> ${localconf}
		if [[ $i == *${network_prime_container}* ]]; then
			echo -n ":net=1" >> ${localconf}
		fi
		echo " \\" >> ${localconf}
	done
	echo " \"" >> ${localconf}

	# Partitioning
	local devsize=""
	if [ -e "/sys/block/$(basename "$target")" ]; then
		TARGET_TYPE=block
	elif [ -d $target ]; then
		TARGET_TYPE=dir
	else
		TARGET_TYPE=image
	fi
	if [ -z "$INSTALL_TYPE" ]; then
		if [ "$TARGET_TYPE" == block ]; then
			INSTALL_TYPE=installer
		else
			INSTALL_TYPE=full
		fi
	fi
	case $TARGET_TYPE in
		block)
			devsize=`blockdev --getsize64 /dev/$(basename "$device")`
			interactive_partition $INSTALL_TYPE $devsize $localconf_dir
			;;
		image)
			# prompt for target size if not defined
			if [ -z "$TARGET_DISK_SIZE" ]; then
				dialog --inputbox "Please input the size of the image file:" 8 100 "7G" 2>$tmpfile
				devsize=$(cat $tmpfile)
				if [ -z "$devsize" ]; then
					debugmsg ${DEBUG_INFO} "Image size not provided. Will use 7G as default."
					echo "TARGET_DISK_SIZE=\"7G\"" >> ${localconf}
					devsize=7516192768
				else
					echo "TARGET_DISK_SIZE=\"$devsize\"" >> ${localconf}
					devsize=`numfmt --from=auto $devsize`
				fi
			else
					devsize=`numfmt --from=auto $TARGET_DISK_SIZE`
			fi
			interactive_partition $INSTALL_TYPE $devsize $localconf_dir
			;;
	esac

	# puppet
	recursive_mkdir ${localconf_dir}/puppet
	echo "" > ${localconf_dir}/puppet/init.pp

	# Add new user
	dialog --no-cancel --inputbox "Create new user:" 8 40 2>$tmpfile
	local username=$(cat $tmpfile)
	if [ -n "$username" ]; then
		local passwd1="" passwd2="" passwdprompt="Please input password:"
		while [ -z "$passwd1" ] || [ -z "$passwd2" ] || [ "$passwd1" != "$passwd2" ]; do
			dialog --no-cancel --inputbox "$passwdprompt" 8 40 2>$tmpfile
			passwd1=$(cat $tmpfile)
			dialog --no-cancel --inputbox "Please confirm password:" 8 40 2>$tmpfile
			passwd2=$(cat $tmpfile)
			passwdprompt="Password mismatch! Please re-input password:"
		done
		local cryptpasswd=$(python -c "import crypt; print crypt.crypt(\"$passwd1\", \"\$6\$\")")
		cat <<EOF >> ${localconf_dir}/puppet/init.pp
group { "$username":
    name => "$username",
    ensure => present,
}

user { "$username":
    ensure => present,
    gid => "$username",
    groups => ["users"],
    membership => minimum,
    shell => "/bin/bash",
    require => [Group["$username"]],
    password => '$cryptpasswd',
}

EOF
	fi

	# Timezone settings
	local tzinfo="/usr/share/zoneinfo"
	while [ ! -f "$tzinfo" ]; do
		if [ "$tzinfo" != "/usr/share/zoneinfo" ]; then
			menuitems=".. .."
		else
			menuitems=""
		fi
		filecount=0
		for i in `ls -1 ${tzinfo}`; do
			menuitems="$menuitems $i $i"
			let filecount++
		done
		dialog --no-tags --menu "Select your time zone:" \
			$(expr $filecount + 7) 100 $filecount $menuitems 2>$tmpfile
		dialog_res=$(cat $tmpfile)
		if [ "$dialog_res" == ".." ]; then
			tzinfo=`dirname $tzinfo`
		elif [ -n "$dialog_res" ]; then
			tzinfo="$tzinfo/$dialog_res"
		fi
	done
	tzinfo=${tzinfo:20}
	cat <<EOF >> ${localconf_dir}/puppet/init.pp
exec { 'set_localtime':
	command => "/bin/ln -sf /usr/share/zoneinfo/${tzinfo} /etc/localtime",
}
file { 'timezone':
	path => "/etc/timezone",
	content => "${tzinfo}",
}

EOF

	# enable puppet
	echo "PUPPETDIR=\"${localconf_dir}/puppet\"" >> ${localconf}
	echo "INSTALL_PUPPET_DIR=\"${localconf_dir}/puppet\"" >> ${localconf}

	# Basic configures
	cat <<EOF >> ${localconf}
EVAL_NAME="OverC Evaluation"

HARDDRIVE_BANNER="Wind River Hard Drive Installer
--------------------------------------------------------------------------------
\$EVAL_NAME
--------------------------------------------------------------------------------"

HARDDRIVE_INTRODUCTION="
This installer will erase all data on your hard drive and configure it to boot
a working Nucleo-T
"

USBSTORAGE_BANNER="USB Creator for the Hard Drive Installer
--------------------------------------------------------------------------------
\$EVAL_NAME
--------------------------------------------------------------------------------"

USBSTORAGE_INTRODUCTION="
This script will erase all data on your USB flash drive and configure it to boot
the Wind River Hard Drive Installer.  This installer will then allow you to
install a working system configuration on to your internal hard drive.
"

INSTALLER_COMPLETE="Installation is now complete"

CMD_GRUB_INSTALL=\`which grub-install\`

INSTALL_GRUBHDCFG="grub-hd.cfg"
INSTALL_GRUBUSBCFG="grub-usb.cfg"
INSTALL_GRUBCFG="\${INSTALLER_FILES_DIR}/\${INSTALL_GRUBUSBCFG}"
INSTALL_FILES="\${INSTALL_KERNEL} \${INSTALL_ROOTFS} \${INSTALL_MODULES} \${INSTALL_GRUBCFG}"
PREREQ_FILES="\${INSTALL_FILES} \${HDINSTALL_ROOTFS} \`strip_properties \${HDINSTALL_CONTAINERS}\`"

BOOTPART_START="63s"
BOOTPART_END="250M"
BOOTPART_FSTYPE="fat32"
BOOTPART_LABEL="OVERCBOOT"

ROOTFS_START="250M"
ROOTFS_END="-1"	# Specify -1 to use the rest of drive
ROOTFS_FSTYPE="ext2"
ROOTFS_LABEL="OVERCINSTROOTFS"

EOF

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

	# make first partition bootable
	/sbin/parted /dev/${device} set 1 boot on > /dev/null 2>&1

	local p1
	local p2
	local try_cnt=0
	# XXX: TODO. the partition name should be returned by create_partition
	# The propagation of the partitions to devfs will sometimes causes a delay
	# Give the system 30 seconds to do the job
	while [ ${try_cnt} -lt 30 ];
	do
		if [ -e /dev/${dev}1 ]; then
			p1="${dev}1"
			p2="${dev}2"
		fi
		if [ -e /dev/${dev}p1 ]; then
			p1="${dev}p1"
			p2="${dev}p2"
		fi
		if [ -n ${p1} ] && [ -n ${p2} ]; then break; fi
		let try_cnt++
		sleep 1
	done
	if [ -z ${p1} ] || [ -z ${p2} ]; then
		debugmsg ${DEBUG_CRIT} "The newly created partition is not propagated by the system. Please retry."
		exit 1
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
	if ${X86_ARCH}; then
		install_grub "${dev}" "${mnt1}"
		assert $?
	else	# arm architecture
		install_dtb "${mnt1}" "${INSTALL_DTB}"
		install_bootloader "${dev}" "${mnt1}" "${INSTALL_BOOTLOADER}" "${BOARD_NAME}"
	fi

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

	clean_up

	# Finish Installation
	display_finalmsg
	
	# Confirm reboot
	if [ ${CONFIRM_REBOOT} -eq 1 ]
	then 
		confirm_reboot
	fi
}
