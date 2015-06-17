#!/bin/bash

#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2 as
#  published by the Free Software Foundation.

#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#  See the GNU General Public License for more details.

BASEDIR=$(readlink -f $(dirname $BASH_SOURCE))
IMAGESDIR="${BASEDIR}/../images"
CONTAINERSDIR="${BASEDIR}/../images/containers"
PACKAGESDIR="${BASEDIR}/../packages"

usage()
{
cat << EOF

  pod-install.sh <rootfs> <device>

EOF
}

if [ -z "$1" ]; then
    usage
    exit
fi

while [ $# -gt 0 ]; do
    case "$1" in
    --config) 
            CONFIG_FILE="$2"
	    shift
            ;;
    -v) verbose=t
            ;;
         *) break
            ;;
    esac
    shift
done

## typical qemu disk is vdb
rootfs=$1
dev=$2

if [ -e "$rootfs" ]; then
    rootfs=`readlink -f $rootfs`
else
    if [ ! -f "${IMAGESDIR}/$rootfs" ]; then
	echo "ERROR: install rootfs ($rootfs) not found"
	exit 1
    fi
    rootfs="${IMAGESDIR}/$rootfs"
fi

# remove /dev/ if specified
dev="`echo $dev | sed 's|/dev/||'`"

# create partitions
# 
#  1: boot
#  2: swap
#  3: root
fdisk /dev/${dev} < ${BASEDIR}/fdisk-a.txt

## create filesystems
mkswap /dev/${dev}2
mkfs.ext4 -v /dev/${dev}1
mkfs.ext4 -v /dev/${dev}3

mkdir -p /z
mount /dev/${dev}3 /z
mkdir /z/boot
mount /dev/${dev}1 /z/boot

## unpack the installation
cd /z
cp /${IMAGESDIR}/pod-builder-initramfs-genericx86-64.cpio.gz boot/initramfs-pod-yocto-standard.img
tar --numeric-owner -xpf $rootfs

final_dev=${dev}
if [ "${dev}" = "vdb" ]; then
    final_dev="vda"
fi

chroot . /bin/bash -c "\\
mount -t devtmpfs none /dev ; \\
mount -t proc none /proc ; \\
mkdir -p /boot/grub; \\
echo \"/dev/${final_dev}1 /boot ext4 defaults 0 0\" >> /etc/fstab ; \\
GRUB_DISABLE_LINUX_UUID=true grub-mkconfig > /boot/grub/grub.cfg ; \\
grub-install /dev/${dev}"

# fixups for virtual installs
if [ "${dev}" = "vdb" ]; then
    sed -i "s/${dev}/${final_dev}/" /z/boot/grub/grub.cfg
fi

if [ -d "${CONTAINERSDIR}" ]; then
    echo "Copying containers to installation"
    mkdir -p /z/tmp
    for c in `ls ${CONTAINERSDIR}`; do
	# containers names are "prefix-<container name>-<... suffixes >
	cname=`basename $c | cut -f2 -d'-'`
	cp ${CONTAINERSDIR}/$c /z/tmp/
	cp ${BASEDIR}/overc-cctl /z/tmp/

	# actually install the container
	if [ "${cname}" == "dom0" ] || [ "${cname}" == "dom1" ]; then
	    chroot . /bin/bash -c "/tmp/overc-cctl add -a -g onboot -t 1 -n $cname -f /tmp/$c"
	else
	    chroot . /bin/bash -c "/tmp/overc-cctl add -t 1 -n $cname -f /tmp/$c"
	fi
    done

    #turn on autostart
    chroot . /bin/bash -c "systemctl enable lxc"    
fi

if [ -d "${PACKAGESDIR}" ]; then
    echo "Copying packages to installation as /opt/packages"
    mkdir -p opt/
    cp -r ${PACKAGESDIR} opt/

    chroot . /bin/bash -c "\\
smart channel -y --add all type=rpm-md baseurl=file://opt/packages/rpm/all/; \\
smart channel -y --add core2_64 type=rpm-md baseurl=file://opt/packages/rpm/core2_64/; \\
smart channel -y --add genericx86_64 type=rpm-md baseurl=file://opt/packages/rpm/genericx86_64; \\
smart channel -y --add lib32_x86 type=rpm-md baseurl=file://opt/packages/rpm/lib32_x86/; \\
smart update"

fi

# cleanup
cd /
umount /z/boot
umount /z/dev
umount /z/proc
umount /z
sync ; sync ; echo 3> /proc/sys/vm/drop_caches
echo o > /proc/sysrq-trigger
