
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
	    echo $(basename ${usbstorage_device})
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
        elif [ "x${driver}" == "xvirtio_blk" ]; then
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

	while partitions=$(${CMD_PARTED} -s /dev/${device} print 2>/dev/null | grep '^ *[0-9]')
	do
		for i in $(echo $partitions | awk '{print $1}')
		do
			debugmsg ${DEBUG_INFO}  "Removing partition $i on /dev/${device}"
			${CMD_PARTED} -s /dev/${device} "rm $i"
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
	${CMD_PARTED} -s /dev/${device} "mkpart primary ${fstype} ${part_start} ${part_end}" > /dev/null 2>&1
	
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

write_grub_cfg()
{
	local base="$1"
	local bootlabel=$2
	local rootlabel=$3
	cat <<EOF >"$4"
set default="0"

serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
terminal_input console serial
terminal_output console serial
set timeout=5

menuentry "$DISTRIBUTION" {
	insmod gzio
	insmod ext2
	insmod fat
	search --no-floppy --label $bootlabel --set=root
	echo	'Loading Linux ...'
	linux	$base/bzImage root=LABEL=$rootlabel ro rootwait $GRUB_KERNEL_PARAMS
	echo	'Loading initial ramdisk ...'
	initrd	$base/initrd
}

menuentry "$DISTRIBUTION recovery" {
        insmod gzio
        insmod ext2
        insmod fat
        search --no-floppy --label $bootlabel --set=root
        echo    'Loading Linux ...'
        linux   $base/bzImage_bakup root=LABEL=$rootlabel rootflags=subvol=rootfs_bakup ro rootwait $GRUB_RECOVERY_KERNEL_PARAMS
        echo    'Loading initial ramdisk ...'
        initrd  $base/initrd
}

EOF
}

write_grub_efi_cfg()
{
	local base="$1"
	local rootlabel=$2
	cat <<EOF >"$3"
set default="0"
set timeout=5
set color_normal='light-gray/black'
set color_highlight='light-green/blue'

menuentry "$DISTRIBUTION" {
       chainloader $base/bzImage root=LABEL=$rootlabel ro rootwait initrd=$base/initrd
}

menuentry "$DISTRIBUTION recovery" {
       chainloader $base/bzImage_bakup root=LABEL=$rootlabel rootflags=subvol=rootfs_bakup ro rootwait initrd=$base/initrd
}

menuentry 'Automatic Key Provision' {
       chainloader /EFI/BOOT/LockDown.efi
}
EOF
}

make_cfg_substitutions()
{
	cfg_file=$1

	if [ -f ${cfg_file} ] && [ -n "${INSTALL_KERNEL}" ]; then
		local kernel_name=`basename ${INSTALL_KERNEL}`
		sed -e "s|%INSTALL_KERNEL%|${kernel_name}|" \
		    -e "s|%INSTALL_INITRAMFS%|initrd|" \
		    -e "s|%INSTALLER_PARTITION%|${p2}|" \
		    -e "s|%ROOTFS_LABEL%|${ROOTFS_LABEL}|" -i ${cfg_file}
		if [ -z "$DISTRIBUTION" ]; then
		        DISTRIBUTION="OverC"
		fi
		sed "s|%DISTRIBUTION%|${DISTRIBUTION}|" -i ${cfg_file}
	else
		debugmsg ${DEBUG_CRIT} "ERROR: Could not update grub configuration with install kernel"
		return 1
	fi
}

install_grub()
{
	local device="$1"
	local bootpoint="$2"
	local mountpoint="$3"
	local efi=""

	# if we are installing to a nbd device, assume that we are working in
	# a virtual environment, and use "vda" as the boot device
	echo ${device} | grep -q nbd
	if [ $? -eq 0 ]; then
	    p2="vda2"
	else
	    p2="${device}2"
	fi

	# Create a mountpoint for bootpoint under mountpoint
	mkdir -p ${mountpoint}/mnt
	mount --bind ${bootpoint} ${mountpoint}/mnt

	debugmsg ${DEBUG_INFO} "[INFO]: installing grub"

	if ! [ -n "$DISTRIBUTION" ]; then
	    DISTRIBUTION="OverC"
	fi

	chroot ${mountpoint} /bin/bash -c "mount -t devtmpfs none /dev"
	chroot ${mountpoint} /bin/bash -c "mount -t proc proc /proc"
	chroot ${mountpoint} /bin/bash -c "mount -t sysfs sys /sys"

	grub_target=`ls ${mountpoint}/usr/lib*/grub/ | grep "efi"`
	if [ $? -eq 0 ]; then
		efi=t
		chroot ${mountpoint} /bin/bash -c "${CMD_GRUB_INSTALL} --target=$grub_target --boot-directory=/mnt --force --removable --efi-directory=/mnt /dev/${device}"
	else
		chroot ${mountpoint} /bin/bash -c "${CMD_GRUB_INSTALL} --target=$grub_target --boot-directory=/mnt --force /dev/${device}"
	fi

	# NOTE: grub-install will install BOOTX64.EFI which will search for the grub.cfg
	# in /boot/grub/grub.cfg. User supplied INSTALL_EFIBOOT firmware files may search
	# for grub.cfg in /boot/EFI/BOOT/ (the current default if using bitbake artifacts)
	debugmsg ${DEBUG_INFO} "[INFO]: setting grub up"
	write_grub_cfg "/images" "OVERCBOOT" "OVERCINSTROOTFS" ${mountpoint}/mnt/grub/grub.cfg

	if [ -n "$efi" ]; then
		if [ -n "${INSTALL_GRUBEFI_CFG}" -a -f "${INSTALL_GRUBEFI_CFG}" ]; then
			debugmsg ${DEBUG_INFO} "[INFO]: Using user supplied config '${INSTALL_GRUBEFI_CFG}'"
			cp -rf "${INSTALL_GRUBEFI_CFG}" ${mountpoint}/mnt/grub/grub.cfg
		else
			debugmsg ${DEBUG_INFO} "[INFO]: Using 'hardcoded' config"
			write_grub_efi_cfg "/images" "OVERCINSTROOTFS" ${mountpoint}/mnt/grub/grub.cfg
		fi
		echo `basename ${mountpoint}/mnt/EFI/BOOT/boot*.efi` >${mountpoint}/mnt/startup.nsh
		make_cfg_substitutions ${mountpoint}/mnt/grub/grub.cfg
		assert $?

		if [ -n "${INSTALL_EFIBOOT}" ] && [ -e "${INSTALL_EFIBOOT}" ]; then
			debugmsg ${DEBUG_INFO} "[INFO]: Installing user supplied EFI '${INSTALL_EFIBOOT}'"
			# Most UEFI will search for BOOTX64.EFI before resorting to startup.nsh
			# so install $INSTALL_EFIBOOT as BOOTX64.EFI to speed up the boot and to
			# prevent the default BOOTX64.EFI installed by grub-install being used.
			cp $INSTALL_EFIBOOT ${mountpoint}/mnt/EFI/BOOT/BOOTX64.EFI
			mv ${mountpoint}/mnt/grub/grub.cfg ${mountpoint}/mnt/EFI/BOOT/
			selsign "${mountpoint}/mnt/EFI/BOOT/grub.cfg"
			echo BOOTX64.EFI >${mountpoint}/mnt/startup.nsh
		fi
		chmod +x ${mountpoint}/mnt/startup.nsh
	fi

	debugmsg ${DEBUG_INFO} "[INFO]: grub installed"

	umount ${mountpoint}/mnt

	chroot ${mountpoint} /bin/bash -c "umount /sys"
	chroot ${mountpoint} /bin/bash -c "umount /proc"
	chroot ${mountpoint} /bin/bash -c "umount /dev"

	return 0
}

install_kernel()
{
	local kernel_src="$1"
	local boot_part="$2"
	local initramfs="$3"
	local initramfs_dest="$4"
	local initramfs_repacked="$5"

	debugmsg ${DEBUG_INFO} "Installing new kernel image to boot partition"

	mkdir -p ${boot_part}/images
	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Failed to create images directory on boot partition"
		return 1
	fi

	debugmsg ${DEBUG_INFO} "Copying ${kernel_src} to <boot>/images"
	cp ${kernel_src} ${boot_part}/images/
	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Failed to copy kernel image to boot partition"
		return 1
	fi

	if [ -f "${kernel_src}.p7b" ]; then
	    debugmsg ${DEBUG_INFO} "Copying ${kernel_src}.p7b to <boot>/images"
	    cp "${kernel_src}.p7b" "${boot_part}/images"
	    if [ $? -ne 0 ]
	    then
		debugmsg ${DEBUG_CRIT} "ERROR: Failed to copy the signature of kernel image to boot partition"
		return 1
	    fi
	fi

	if [ -n ${initramfs} ]; then
	        debugmsg ${DEBUG_INFO} "Copying ${initramfs} to <boot>/images/${initramfs_dest}"
		cp ${initramfs} ${boot_part}/images/${initramfs_dest}
		if [ $? -ne 0 ]
		then
			debugmsg ${DEBUG_CRIT} "ERROR: Failed to copy initramfs image to boot partition"
			return 1
		fi

		if [ -f "${initramfs}.p7b" ]; then
		    if [ -n "${initramfs_repacked}" ]; then
			selsign "${boot_part}/images/${initramfs_dest}"
		    else
			cp "${initramfs}.p7b" "${boot_part}/images/${initramfs_dest}.p7b"
			if [ $? -ne 0 ]
			then
			    debugmsg ${DEBUG_CRIT} "ERROR: Failed to copy the signature of initramfs image to boot partition"
			    return 1
			fi
		    fi
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

    if [ -d "${TMPMNT}/opt/container/${cname}/rootfs/lib/systemd/system/" ]; then
	tgt="${TMPMNT}/opt/container/${cname}/rootfs/lib/systemd/system/"
    else
	if [ -d "${TMPMNT}/opt/container/${cname}/rootfs/usr_temp" ]; then
	    tgt="${TMPMNT}/opt/container/${cname}/rootfs/usr_temp/lib/systemd/system"
	fi
    fi

    if [ -n "${tgt}" ]; then
	mkdir -p ${tgt}
	# copy service
	cp -f "${service}" ${tgt}/${sname}
	# activate service
	ln -sf /lib/systemd/system/${sname} ${TMPMNT}/opt/container/${cname}/rootfs/etc/systemd/system/multi-user.target.wants/${sname}
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

    if [ -d "${TMPMNT}/opt/container/${cname}/rootfs/lib/systemd/system/" ]; then
	tgt="${TMPMNT}/opt/container/${cname}/rootfs/lib/systemd/system/"
    else
	if [ -d "${TMPMNT}/opt/container/${cname}/rootfs/usr_temp" ]; then
            echo bar bar
	    tgt="${TMPMNT}/opt/container/${cname}/rootfs/usr_temp/lib/systemd/system"
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
    sockets=$(basename --suffix .service ${services})
    sockets="${sockets}.socket"
    local debug_msg="[INFO]: Can not find the service ${services} to disable"

    if [ -z "${cname}" ]; then
        # For essential
        slinks=$(find ${TMPMNT}/etc/systemd/ -name ${services} 2>/dev/null)
        sockets=$(find ${TMPMNT}/etc/systemd/ -name ${sockets} 2>/dev/null)
        debug_msg="${debug_msg} for essential."
    else
        # For containers
        slinks=$(find ${TMPMNT}/opt/container/${cname}/rootfs/etc/systemd/ -name ${services} 2>/dev/null)
        sockets=$(find ${TMPMNT}/opt/container/${cname}/rootfs/etc/systemd/ -name ${sockets} 2>/dev/null)
        debug_msg="${debug_msg} for ${cname}."
    fi

    if [ -z "${slinks}" ]; then
        debugmsg ${DEBUG_INFO} ${debug_msg}
        return 1
    fi
    rm -f ${slinks} ${sockets}
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
    local spaths=`find ${TMPMNT}/opt/container/${cname}/rootfs/lib/systemd/ \
                       ${TMPMNT}/opt/container/${cname}/rootfs/usr/lib/systemd/ \
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
	local extra_opts=""

	if [ ${DO_IMA_SIGN} -eq 1 ]; then
		extra_opts="--xattrs --xattrs-include=security\\.ima"
	fi

	tar ${extra_opts} -jxf "${tarball_src}" -C "${destination}" &
	pidspinner "$!" "1"

	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Failed to extract tarball ${tarball_src} to ${destination}"
		return 1
	fi

	return 0
}

pack_tarball()
{
	local dir="$1"
	local tarball="$2"
	local extra_opts=""

	if [ ${DO_IMA_SIGN} -eq 1 ]; then
		extra_opts="--xattrs --xattrs-include=security\\.ima"
	fi

	(
		cd "${dir}"
		tar ${extra_opts} -cjf "${tarball}" *
	) &
	pidspinner "$!" "1"

	if [ $? -ne 0 ]
	then
		debugmsg ${DEBUG_CRIT} "ERROR: Failed to pack tarball ${tarball} from ${dir}"
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
	umount_partitions "$device"
	assert $?

	## Create GPT table unless MBR(msdos) is desired. Since we are creating
	## a new partition table there is no need to remove existing partitions.
	if [ -n "$INSTALL_USE_GPT" ]
	then
	    debugmsg ${DEBUG_INFO} "Creating new GPT partition table"
	    ${CMD_PARTED} -s /dev/${device} "mklabel gpt" > /dev/null 2>&1
	else
	    debugmsg ${DEBUG_INFO} "Creating new MBR partition table"
	    ${CMD_PARTED} -s /dev/${device} "mklabel msdos" > /dev/null 2>&1
	fi
	
	## Create new partitions
	debugmsg ${DEBUG_INFO} "Creating new partitions"
	create_partition "${device}" 1 ${BOOTPART_FSTYPE} ${BOOTPART_START} ${BOOTPART_END}
	assert $?
	create_partition "${device}" 2 ${ROOTFS_FSTYPE} ${ROOTFS_START} ${ROOTFS_END}
	assert $?

	# make first partition bootable
	${CMD_PARTED} /dev/${device} set 1 boot on > /dev/null 2>&1

	local p1
	local p2
	local try_cnt=0
	# XXX: TODO. the partition name should be returned by create_partition
	# The propagation of the partitions to devfs will sometimes causes a delay
	# Give the system 30 seconds to do the job
	while [ ${try_cnt} -lt 30 ];
	do
		if [ -e /dev/${device}1 ]; then
			p1="${device}1"
			p2="${device}2"
		fi
		if [ -e /dev/${device}p1 ]; then
			p1="${device}p1"
			p2="${device}p2"
		fi
		if [ -n "${p1}" ] && [ -n "${p2}" ]; then break; fi
		let try_cnt++
		sleep 1
	done
	if [ -z ${p1} ] || [ -z ${p2} ]; then
		debugmsg ${DEBUG_CRIT} "The newly created partition is not propagated by the system. Please retry."
		exit 1
	fi

	## Create new filesystems
	debugmsg ${DEBUG_INFO} "Creating new filesystems "
	if [ -z "$BOOTPART_LABEL" ]; then
		BOOTPART_LABEL=OVERCBOOT
	fi
	debugmsg ${DEBUG_INFO} "Creating Partition:${p1} Type:${BOOTPART_FSTYPE} Label:${BOOTPART_LABEL}"
	create_filesystem "${p1}" "${BOOTPART_FSTYPE}" "${BOOTPART_LABEL}"
	assert $?

	if [ -z "$ROOTFS_LABEL" ]; then
		ROOTFS_LABEL=OVERCINSTROOTFS
	fi
	debugmsg ${DEBUG_INFO} "Creating Partition:${p2} Type:${ROOTFS_FSTYPE} Label:${ROOTFS_LABEL}"
	create_filesystem "${p2}" "${ROOTFS_FSTYPE}" "${ROOTFS_LABEL}"
	assert $?

	## Create temporary mount points
	mnt1=$(tmp_mount "${p1}")
	assert $?
	
	mnt2=$(tmp_mount "${p2}")
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

	## Install Bootloader
	if ${X86_ARCH}; then
		install_grub "${device}" "${mnt1}" "${mnt2}"
		assert $?
	else	# arm architecture
		install_dtb "${mnt1}" "${INSTALL_DTB}"
		install_bootloader "${device}" "${mnt1}" "${INSTALL_BOOTLOADER}" "${BOARD_NAME}"
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

# make menuitems function
# param #1: the item list
# param #2: optional. If present, it will be regarded as the checklist default status
# return: the item count
format_menuitems()
{
	menuitems=""
	local itemlist=$1
	local checklistswitch=$2
	local itemcount=0
	for i in $itemlist; do
		menuitems="$menuitems $i $i $checklistswitch"
		let itemcount++
	done
	return $itemcount
}

verify_commands()
{
	if [ -z "$CMD_GRUB_INSTALL" ] || [ ! -e "$CMD_GRUB_INSTALL" ]; then
		CMD_GRUB_INSTALL=$(which grub-install)

		if [ ! -e "$CMD_GRUB_INSTALL" ]; then
			debugmsg ${DEBUG_INFO} "ERROR: Could not find grub-install"
			false
			assert $?
		fi
	fi

	if [ -z "$CMD_PARTED" ] || [ ! -e "$CMD_PARTED" ]; then
		CMD_PARTED=$(which parted)

		if [ ! -e "$CMD_PARTED" ]; then
			debugmsg ${DEBUG_INFO} "ERROR: Could not find parted"
			false
			assert $?
		fi
	fi
}
