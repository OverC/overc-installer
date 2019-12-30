override_function install_bootloader
override_function install_dtb
install_bootloader()
{
	local device="$1"
	local mountpoint="$2"
	local bootloader="$3"
	local boardname="$4"
	local dtb_overlays="at86rf233.dtbo \
		dwc2.dtbo \
		gpio-key.dtbo \
		hifiberry-amp.dtbo \
		hifiberry-dac.dtbo \
		hifiberry-dacplus.dtbo \
		hifiberry-digi.dtbo \
		i2c-rtc.dtbo \
		iqaudio-dac.dtbo \
		iqaudio-dacplus.dtbo \
		mcp2515-can0.dtbo \
		pi3-disable-bt.dtbo \
		pi3-miniuart-bt.dtbo \
		pitft22.dtbo \
		pitft28-resistive.dtbo \
		pitft35-resistive.dtbo \
		pps-gpio.dtbo \
		rpi-ft5406.dtbo \
		rpi-poe.dtbo \
		vc4-kms-v3d.dtbo \
		vc4-fkms-v3d.dtbo \
		w1-gpio-pullup.dtbo \
		w1-gpio.dtbo"

	# bootloader is actually a directory including 
	# first stage bootloader imageand required firmwares
	if ! [ -d "$bootloader" ]; then
		debugmsg ${DEBUG_CRIT} "INFO: didn't find bootloader file $bootloader"
		return 0
	fi

	local boot_artifacts_dir=`dirname $bootloader`
	local u_boot="$boot_artifacts_dir/u-boot.bin"
	local config_txt="$boot_artifacts_dir/config.txt"

	if ! [ -f "$u_boot" ]; then
		debugmsg ${DEBUG_CRIT} "INFO: didn't find u-boot image $u_boot"
		return 0
	fi

	
	if ! [ -f "$config_txt" ]; then
		debugmsg ${DEBUG_CRIT} "INFO: didn't find config file $config_txt"
		return 0
	fi

	# These are actually boot files including first stage bootloader and firmwares.
	install $bootloader/* $mountpoint/

	# There is a first stage bootloader, and it boots image with the name "kernel8.img",
        # which is hard-coded 'kernel8.img' in it, no matter it boots kernel or next stage bootloader.
	# We prefer to boot u-boot image before booting kernel.
	install $u_boot $mountpoint/kernel8.img

	# This config file is required by first stage bootloader
	install $config_txt $mountpoint/

	# Install dtb overlays
	mkdir -p $mountpoint/overlays

	for file in $dtb_overlays
	do
		install ${boot_artifacts_dir}/$file $mountpoint/overlays/
	done

}

install_dtb()
{
	local mountpoint="$1"
	local dtb="$2"
	## Copy the dtb file
	if [ -e "$dtb" ]; then
		debugmsg ${DEBUG_CRIT} "INFO: found dtb "
		cp $dtb ${mountpoint}/
	else
		debugmsg ${DEBUG_CRIT} "ERROR: cannot find dtb file $dtb"
		return 1
	fi
}
