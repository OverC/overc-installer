override_function install_bootloader
install_bootloader()
{
	local device="$1"
	local mountpoint="$2"
	local bootloader="$3"
	local boardname="$4"
	local bootloader_env="$5"

	if ! [ -e "$bootloader" ]; then
		debugmsg ${DEBUG_CRIT} "INFO: didn't find bootloader file $bootloader"
		return 0
	fi

	#put the bootloader into the location from 8th section of boot device.
	BS=512
	SEEK=8
	dd if=$bootloader of=/dev/$device bs=$BS seek=$SEEK conv=notrunc oflag=sync
	if [ -e "$bootloader_env" ]; then
		#put the u-boot env into the location from 2048th section of boot device
		SEEK=2048
		dd if=$bootloader_env of=/dev/$device bs=$BS seek=$SEEK conv=notrunc oflag=sync
	fi
}
