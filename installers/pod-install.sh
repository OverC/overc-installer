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
if [ $btrfs -eq 0 ]; then
	mkfs.ext4 -v /dev/${dev}3
else
	mkfs.btrfs -f /dev/${dev}3
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
cp /${IMAGESDIR}/*-initramfs-*-64.cpio.gz boot/initramfs-pod-yocto-standard.img
tar --numeric-owner -xpf $rootfs

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
	cname=$( extract_container_name $c )
	echo ${cname} | grep -qi error
	if [ $? == 0 ]; then
	    # We got an error instead of the cname.  Show the user.
	    echo ${cname}
	    exit 1
	fi
	cp ${CONTAINERSDIR}/$c /z/tmp/
	cp ${BASEDIR}/overc-cctl /z/tmp/

	# actually install the container
	if [ "${cname}" == "dom0" ]; then
	    chroot . /bin/bash -c "/tmp/overc-cctl add -d -a -g onboot -t 0 -n $cname -f /tmp/$c"
        elif [ "${cname}" == "dom1" ]; then
	    chroot . /bin/bash -c "/tmp/overc-cctl add -d -p -g peer -t 0 -n $cname -f /tmp/$c"
	else
	    chroot . /bin/bash -c "/tmp/overc-cctl add -d -p -g peer -t 0 -n $cname -f /tmp/$c"
	fi
    done
    
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
