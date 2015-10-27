override_function install_bootloader
install_bootloader()
{
	local device="$1"
	local mountpoint="$2"
	local bootloader="$3"
	local boardname="$4"

	if ! [ -e "$bootloader" ]; then
		debugmsg ${DEBUG_CRIT} "INFO: didn't find bootloader file $bootloader"
		return 0
	fi

	install $bootloader $mountpoint/boot.bin
}
