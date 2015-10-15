#!/bin/bash

BASEDIR=$(readlink -f $(dirname $BASH_SOURCE))
IMAGESDIR="${BASEDIR}/../images"
CONTAINERSDIR="${BASEDIR}/../images/containers"
PACKAGESDIR="${BASEDIR}/../packages"
PUPPETDIR="${BASEDIR}/../files/puppet"

usage()
{
cat << EOF

  pod-install.sh <rootfs> <device>

    -b: use btrfs
    --finaldev: boot from this block dev. Default is vda
    --ttyconsoledev: set dev used for tty console
    --ttyconsolecn: set container name for providing agetty

EOF
}

function extract_container_name
{
    # Parms: $1 = filename
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

if [ -z "$1" ]; then
    usage
    exit
fi

btrfs=0
ttyconsolecn=""
ttyconsoledev="ttyS0"
while [ $# -gt 0 ]; do
    case "$1" in
    --config) 
            CONFIG_FILE="$2"
	    shift
            ;;
    -v) verbose=t
            ;;
    -b) btrfs=1
            ;;
    --finaldev) final_dev="$2"
            shift
            ;;
    --ttyconsoledev) ttyconsoledev="$2"
            shift
            ;;
    --ttyconsolecn) ttyconsolecn="$2"
            shift
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
#  4. lxc

BOOTLABEL="OVERCBOOT"
SWAPLABEL="SWAP"
ROOTLABEL="OVERCROOTFS"
LXCLABEL="OVERCCN"

fdisk /dev/${dev} < ${BASEDIR}/fdisk-4-partition-layout.txt 

## create filesystems
mkswap -L $SWAPLABEL /dev/${dev}2
mkfs.vfat -n $BOOTLABEL /dev/${dev}1
if [ $btrfs -eq 0 ]; then
	mkfs.ext4 -v -L $ROOTLABEL /dev/${dev}3
	mkfs.ext4 -v -L $LXCLABEL /dev/${dev}4
else
	mkfs.btrfs -f -L $ROOTLABEL /dev/${dev}3
	mkfs.btrfs -f -L $LXCLABEL /dev/${dev}4
fi

mkdir -p /z
mount /dev/${dev}3 /z


if [ $btrfs -eq 0 ]; then
	mkdir /z/boot
	mount /dev/${dev}1 /z/boot
else
	# create a subvolume
	btrfs subvolume create /z/rootfs

	mkdir /z/rootfs/boot
	mount /dev/${dev}1 /z/rootfs/boot
fi


## unpack the installation
if [ $btrfs -eq 0 ]; then
	cd /z
else
	cd /z/rootfs
fi

## vfat filesystem doesn't support soft link, here umount boot partition and
## then copy kernel image to boot partition
umount boot 
tar --numeric-owner -xpf $rootfs

mount /dev/${dev}1 mnt
chroot . /bin/bash -c "\\
	cp /boot/bzImage* /mnt; \\
"
umount ./mnt
mount /dev/${dev}1 boot

kernel=`basename boot/bzImage-*`
kernel_version=`echo $kernel | sed 's/^[^0-9]*-//g'`
initrd="initrd-${kernel_version}.gz"
cp /${IMAGESDIR}/*-initramfs-*-64.cpio.gz boot/${initrd}

if [ $btrfs -eq 1 ]; then
	# get the subvolume id of /mnt/rootfs using:
	subvol=`btrfs subvolume list /z/rootfs | awk '{print $2;}'`
	# set default volume when mounted
	btrfs subvolume set-default $subvol /z/rootfs

	cd /
	umount /z/rootfs/boot
	umount /z/
	mount -o subvolid=${subvol} /dev/${dev}3 /z
	mount /dev/${dev}1 /z/boot
	cd /z/
fi

if [ -z ${final_dev} ]; then
	final_dev=${dev}
	if [ "${dev}" = "vdb" ]; then
		final_dev="vda"
	fi
fi

chroot . /bin/bash -c "\\
mount -t devtmpfs none /dev ; \\
mount -t proc none /proc ; \\
mkdir -p /boot/grub; \\
echo \"LABEL=$SWAPLABEL none swap sw 0 0\" >> /etc/fstab ; \\
echo \"LABEL=$BOOTLABEL /boot auto defaults 0 0\" >> /etc/fstab ; \\
echo \"LABEL=$LXCLABEL /var/lib/lxc auto defaults 0 0\" >> /etc/fstab ; \\
GRUB_DISABLE_LINUX_UUID=true grub-mkconfig > /boot/grub/grub.cfg ; \\
grub-install /dev/${dev}"

# fixups for virtual installs
if [ "${dev}" = "vdb" ]; then
    sed -i "s/${dev}/${final_dev}/" /z/boot/grub/grub.cfg
fi

if [ -e /${IMAGESDIR}/boot*.efi ]; then
       mkdir -p boot/EFI/BOOT
       cp /${IMAGESDIR}/boot*.efi boot/EFI/BOOT
       # remove those sections that are supported by uefi grub,
       # such as if/else statement and functions and only keep
       # grub menuentry section.
       cat /z/boot/grub/grub.cfg | sed -n '/### BEGIN \/etc\/grub.d\/10_linux ###/,/### END \/etc\/grub.d\/10_linux ###/p' >boot/EFI/BOOT/grub.cfg
       sed -i "s/bzImage-${kernel_version}/bzImage/" boot/EFI/BOOT/grub.cfg
       sed -i '/load_/d' boot/EFI/BOOT/grub.cfg
       sed -i '/insmod/d' boot/EFI/BOOT/grub.cfg
       sed -i '/if \[/,/fi *$/d' boot/EFI/BOOT/grub.cfg
       sed -i '/echo/d' boot/EFI/BOOT/grub.cfg

       echo `basename boot/EFI/BOOT/boot*.efi` >boot/startup.nsh
else
       cp ${BASEDIR}/startup.nsh boot/
       sed -i "s/%ROOTLABEL%/${ROOTLABEL}/" boot/startup.nsh
       sed -i "s/%INITRD%/${initrd}/" boot/startup.nsh
       sed -i "s/%BZIMAGE%/bzImage/" boot/startup.nsh
fi
chmod +x boot/startup.nsh

if [ -d "${CONTAINERSDIR}" ]; then
    echo "Copying containers to installation"
    if [ ! -d /z/var/lib/lxc ]; then
        mkdir -p /z/var/lib/lxc
    fi
    mount /dev/${dev}4 /z/var/lib/lxc

    mkdir -p /z/tmp
    # Because peer container deployment needs to write into the rootfs
    # space of dom0, we must ensure that dom0, if there, gets deployed first.
    # To accomplish that, we have to make sure that dom0 ends up at
    # the beginning of the ls list.
    for c in $(ls ${CONTAINERSDIR} | grep '\-dom0\-' ; ls ${CONTAINERSDIR} | grep -v '\-dom0\-' ); do
	# containers names are "prefix-<container name>-<... suffixes >
	cname=$( extract_container_name $c )
	echo ${cname} | grep -qi error
	if [ $? == 0 ]; then
	    # We got an error instead of the cname.  Show the user.
	    echo ${cname}
	    exit 1
	fi
	cp ${CONTAINERSDIR}/$c /z/tmp/
	cp ${BASEDIR}/overc-cctl /z/tmp/

    ttyconsole_opt="-S ${ttyconsoledev}"
    if [ "${ttyconsolecn}" == "${cname}" ]; then
        ttyconsole_opt="-s ${havettyconsole_opt}"
    fi

	# actually install the container
	if [ "${cname}" == "dom0" ]; then
	    chroot . /bin/bash -c "/tmp/overc-cctl add -d -a -g onboot -t 0 -n $cname -f /tmp/$c ${ttyconsole_opt}"
        elif [ "${cname}" == "dom1" ]; then
	    chroot . /bin/bash -c "/tmp/overc-cctl add -d -p -g peer -t 0 -n $cname -f /tmp/$c ${ttyconsole_opt}"
	else
	    chroot . /bin/bash -c "/tmp/overc-cctl add -d -p -g peer -t 0 -n $cname -f /tmp/$c ${ttyconsole_opt}"
	fi
    done

    umount /z/var/lib/lxc
    
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

if [ -d ${PUPPETDIR} ]; then
    echo "Running puppet"
    cd /z
    cp -r ${PUPPETDIR} tmp/.

    chroot . /bin/bash -c " \\
if [ $(which puppet 2> /dev/null) ]; then \\
    puppet apply /tmp/puppet/init.pp ; \\
else \\
    echo \"Puppet not found on rootfs. Not applying puppet configuration.\" ; \\
fi ; \\
"
fi

# cleanup
cd /
umount /z/boot
umount /z/dev
umount /z/proc
umount /z
sync ; sync ; echo 3> /proc/sys/vm/drop_caches
echo o > /proc/sysrq-trigger
