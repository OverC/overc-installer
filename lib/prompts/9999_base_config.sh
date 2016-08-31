#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2 as
#  published by the Free Software Foundation.

#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#  See the GNU General Public License for more details.

# Base config, currently no prompts yet. To be added later if required.

base_config()
{
	cat <<EOF >> ${tmpconf}
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

CONFIRM_REBOOT=0

EOF
}
