#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2 as
#  published by the Free Software Foundation.

#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#  See the GNU General Public License for more details.

# Partition related prompts

# To be compatible with 2.20.1 fdisk format, we need to use integer.
# Lines use this can be replaced with the following after fdisk is upgraded:
# numfmt --to=iec --from=iec --round=down ${bootpartsize}
convert_to_M()
{
	local size=`numfmt --from=iec $1`
	awk "BEGIN {printf \"%d\", $size/1048576}"
}

partition_config()
{
	local tmpfile=$(mktemp)
	# define if this is an installer image
	# If this is an installer image, we provide only two partitions for user to choose.
	# If this is an live/harddrive image, we provide four partitions for user to configure.
	local lastsize=0
	local tmppartitionlayout="${SAVE_CONFIG_FOLDER}/fdisk-4-partition-user-layout.txt"
	local size=0

	if [ -z "$target" ] && [ -n "$raw_dev" ]; then
		target=$raw_dev
	fi
	if [ -z "$TARGET_TYPE" ]; then
		if [ -e "/sys/block/$(basename "$target")" ]; then
			TARGET_TYPE=block
		elif [ -d $target ]; then
			TARGET_TYPE=dir
		else
			TARGET_TYPE=image
		fi
	fi
	case $TARGET_TYPE in
		block)
			size=`blockdev --getsize64 /dev/$(basename "$target")`
			;;
		image)
			# prompt for target size if not defined
			if [ -z "$TARGET_DISK_SIZE" ]; then
				dialog --inputbox "Please input the size of the image file:" 8 100 "7G" 2>$tmpfile
				size=$(cat $tmpfile)
				if [ -z "$size" ]; then
					debugmsg ${DEBUG_INFO} "Image size not provided. Will use 7G as default."
					echo "TARGET_DISK_SIZE=\"7G\"" >> ${tmpconf}
					size=7516192768
				else
					echo "TARGET_DISK_SIZE=\"$size\"" >> ${tmpconf}
					size=`numfmt --from=iec $size`
				fi
			else
				size=`numfmt --from=iec $TARGET_DISK_SIZE`
			fi
			;;
	esac

	if [ -z "$INSTALL_TYPE" ]; then
		if [ "$TARGET_TYPE" == block ]; then
			INSTALL_TYPE=installer
		else
			INSTALL_TYPE=full
		fi
	fi

	local prompt="Destinition device will be partitioned using the following schema: \n"
	if [ "$INSTALL_TYPE" == "installer" ]; then
		lastsize=`numfmt --to=iec --round=down $(expr $size - 268435456)`
		prompt="$prompt 1) boot (250M) \n 2) root ($lastsize)"
	else
		containerpartsize=`numfmt --to=iec --round=down $(expr $size - 3221225472)`
		prompt="$prompt 1) boot (250M) \n 2) swap (768M) \n 3) root (2G) \n 4) containers ($containerpartsize)"
	fi
	dialog --yesno "$prompt" 10 80
	dialog_res=$?
	if [ $dialog_res -eq 0 ]; then
		# User answered yes. Just use default
		if [ "$INSTALL_TYPE" == "installer" ]; then
			bootpartsize="250M"
			rootfspartsize="-1"
		else
			bootpartsize="250M"
			swappartsize="768M"
			rootfspartsize="2048M"
		fi
	else
		# User answered no. Prompt for sizes.
		# TODO:
		#   1.Let user do manual partition layout
		#   2.Do value sanity check
		if [ "$INSTALL_TYPE" == "installer" ]; then
			dialog --no-cancel --inputbox "Boot partition size:" 8 40 "250M" 2>$tmpfile
			bootpartsize=`numfmt --from=iec $(cat $tmpfile)`
			lastsize=`numfmt --to=iec $(expr $size - ${bootpartsize} - 2097152)`
			dialog --no-cancel --inputbox "Rootfs partition size:" 8 40 "${lastsize}" 2>$tmpfile
			rootfspartsize=$(cat $tmpfile)
		else
			dialog --no-cancel --inputbox "Boot partition size:" 8 40 "250M" 2>$tmpfile
			bootpartsize=`numfmt --from=iec $(cat $tmpfile)`
			dialog --no-cancel --inputbox "Swap partition size:" 8 40 "768M" 2>$tmpfile
			swappartsize=`numfmt --from=iec $(cat $tmpfile)`
			dialog --no-cancel --inputbox "Rootfs partition size:" 8 40 "2G" 2>$tmpfile
			rootfspartsize=`numfmt --from=iec $(cat $tmpfile)`
			dialog --no-cancel --inputbox "Containers partition size:" 8 40 \
				"`numfmt --to=iec --round=down $(expr $size - ${bootpartsize} - ${swappartsize} - ${rootfspartsize} - 2097152)`" 2>$tmpfile
			containerpartsize=$(cat $tmpfile)
		fi
	fi
	if [ "$INSTALL_TYPE" == "installer" ]; then
		echo "BOOTPART_START=\"63s\"" >> ${tmpconf}
		echo "BOOTPART_END=\"${bootpartsize}\"" >> ${tmpconf}
		echo "BOOTPART_FSTYPE=\"fat32\"" >> ${tmpconf}
		echo "BOOTPART_LABEL=\"OVERCBOOT\"" >> ${tmpconf}
		echo "ROOTFS_START=\"${bootpartsize}\"" >> ${tmpconf}
		if [ ${rootfspartsize} == "-1" ]; then
			echo "ROOTFS_END=\"${rootfspartsize}\"" >> ${tmpconf}
		else
			echo "ROOTFS_END=\"$(expr `numfmt --from=iec $bootpartsize` + `numfmt --from=iec $rootfspartsize`)\"" >> ${tmpconf}
		fi
		echo "ROOTFS_FSTYPE=\"ext2\"" >> ${tmpconf}
		echo "ROOTFS_LABEL=\"OVERCINSTROOTFS\"" >> ${tmpconf}
	else
		cat <<EOF > ${tmppartitionlayout}
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

+$(convert_to_M ${bootpartsize})M
n
p
2

+$(convert_to_M ${swappartsize})M
n
p
3

+$(convert_to_M ${rootfspartsize})M
n
p

+$(convert_to_M ${containerpartsize})M
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
		echo "FDISK_PARTITION_LAYOUT=\"${tmppartitionlayout}\"" >> ${tmpconf}
	fi

	rm $tmpfile
}
