#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2 as
#  published by the Free Software Foundation.

#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#  See the GNU General Public License for more details.

# Artifacts related prompts

artifacts_config()
{
	local tmpfile=$(mktemp)
	local filecount=0
	local filelist=""

	if [ -z "$ARTIFACTS_DIR" ]; then
		if [ -e "images" ]; then
			ARTIFACTS_DIR="`pwd`/images"
		else
			# default to current dir
			ARTIFACTS_DIR="`pwd`"
		fi
	fi

	echo "ARTIFACTS_DIR=\"${ARTIFACTS_DIR}\"" >> ${tmpconf}
	filecount=`ls $ARTIFACTS_DIR -1 | grep -v manifest | wc -l`
	if [ $filecount -lt 3 ]; then
		debugmsg ${DEBUG_CRIT} "Artifacts are not sufficient. Please verify."
		return 1
	fi

	# Kernel selection
	filelist=`ls $ARTIFACTS_DIR | grep -E "(.*[uz]Image.*)|(.*vmlinu[xz].*)"`
	if [ -z "$filelist" ]; then
		debugmsg ${DEBUG_CRIT} "Kernel file not found. Please specify the correct artifacts dir."
		return 1
	fi
	format_menuitems "$filelist"
	filecount=$?
	dialog --no-tags --menu "Please choose kernel:" \
		$(expr $filecount + 7) 100 $filecount $menuitems 2>$tmpfile
	dialog_res=$(cat $tmpfile)
	if [ -z "${dialog_res}" ]; then
		debugmsg ${DEBUG_CRIT} "Kernel not specified. Please try again."
		return 1
	fi
	echo "INSTALL_KERNEL=\"\${ARTIFACTS_DIR}/${dialog_res}\"" >> ${tmpconf}

	# Initramfs selection
	filelist=`ls $ARTIFACTS_DIR | grep initramfs | grep -v manifest`
	format_menuitems "$filelist"
	filecount=$?
	dialog --no-tags --menu "Please choose initramfs:" \
		$(expr $filecount + 7) 100 $filecount $menuitems 2>$tmpfile
	dialog_res=$(cat $tmpfile)
	if [ -z "${dialog_res}" ]; then
		debugmsg ${DEBUG_CRIT} "Initramfs not specified. Please try again."
		return 1
	fi
	echo "INSTALL_INITRAMFS=\"\${ARTIFACTS_DIR}/${dialog_res}\"" >> ${tmpconf}

	# Rootfs selection
	filelist=`ls $ARTIFACTS_DIR | grep essential | grep -v manifest`
	format_menuitems "$filelist"
	filecount=$?
	dialog --no-tags --menu "Please choose rootfs:" \
		$(expr $filecount + 7) 100 $filecount $menuitems 2>$tmpfile
	dialog_res=$(cat $tmpfile)
	if [ -z "${dialog_res}" ]; then
		debugmsg ${DEBUG_CRIT} "Rootfs not specified. Please try again."
		return 1
	fi
	echo "INSTALL_ROOTFS=\"\${ARTIFACTS_DIR}/${dialog_res}\"" >> ${tmpconf}
	echo "HDINSTALL_ROOTFS=\"\${ARTIFACTS_DIR}/${dialog_res}\"" >> ${tmpconf}

	# containers selection
	if [ -d "$ARTIFACTS_DIR/containers" ]; then
		filelist=`ls $ARTIFACTS_DIR/containers`
	else
		filelist=`ls $ARTIFACTS_DIR | grep tar`
	fi
	format_menuitems "$filelist" off
	filecount=$?
	dialog --no-tags --checklist "Please choose install containers:" \
		$(expr $filecount + 7) 100 $filecount $menuitems 2>$tmpfile
	dialog_res=$(cat $tmpfile)
	if [ -z "${dialog_res}" ]; then
		debugmsg ${DEBUG_CRIT} "Containers not specified. Please try again."
		return 1
	fi

	hdcontainers=${dialog_res} fmtcontainers=""

	# VT and network prime selection
	menuitems=""
	filecount=0
	for i in ${hdcontainers}; do
		if [ -d "$ARTIFACTS_DIR/containers" ]; then
			fmtcontainers="$fmtcontainers containers/$i"
		else
			fmtcontainers="$fmtcontainers $i"
		fi
		menuitems="$menuitems $i $i"
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
	network_prime_container=$(cat $tmpfile)
	if [ -z "${network_prime_container}" ]; then
		debugmsg ${DEBUG_INFO} "Network prime containers not specified."
	else
		# Define network device
		dialog --inputbox "Please provide the network device to be used in the network prime container:" 8 100 "all" 2>$tmpfile
		dialog_res=$(cat $tmpfile)
		if [ -n "$dialog_res" ]; then
			echo "NETWORK_DEVICE=\"${dialog_res}\"" >> ${tmpconf}
		fi
	fi

	# Format HDINSTALL_CONTAINERS configuration
	echo "HDINSTALL_CONTAINERS=\" \\" >> ${tmpconf}
	for i in ${fmtcontainers}; do
		echo -n " \${ARTIFACTS_DIR}/${i}" >> ${tmpconf}
		if [[ $i == *${network_prime_container}* ]]; then
			echo -n ":net=1" >> ${tmpconf}
		fi
		echo " \\" >> ${tmpconf}
	done
	echo " \"" >> ${tmpconf}

	rm $tmpfile
}
