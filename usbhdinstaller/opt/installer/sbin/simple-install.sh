#!/bin/bash

usage()
{
cat << EOF

  simple-install.sh <rootfs> <device>

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

if [ ! -f "$rootfs" ]; then
    echo "ERROR: install rootfs ($rootfs) not found"
    exit 1
fi

# remove /dev/ if specified
dev="`echo $dev | sed 's|/dev/||'`"

# create partitions
# 
#  1: boot
#  2: swap
#  3: root
fdisk /dev/${dev} < fdisk-a.txt

## create filesystems
mkswap /dev/${dev}2
mkfs.ext4 -v /dev/${dev}1
mkfs.ext4 -v /dev/${dev}3
mkdir /z
mount /dev/${dev}3 /z
mkdir /z/boot
mount /dev/${dev}1 /z/boot

## unpack the installation
cd /z
cp /inst/pod-builder-initramfs-genericx86-64.cpio.gz boot/initramfs-pod-yocto-standard.img
tar --numeric-owner -xpf /inst/$rootfs

chroot . /bin/bash -c "\\
mount -t devtmpfs /dev /dev ; \\
mount -t proc none /proc ; \\
mkdir -p /boot/grub; \\
echo \"/dev/${dev}1 /boot ext4 defaults 0 0\" >> /etc/fstab ; \\
GRUB_DISABLE_LINUX_UUID=true grub-mkconfig > /boot/grub/grub.cfg ; \\
grub-install /dev/${dev}"

if [ -d "/inst/packages" ]; then
    echo "Copying packages to installation as /opt/packages"
    mkdir -p opt/
    cp -r /inst/packages opt/

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
