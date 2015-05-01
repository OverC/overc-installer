#!/bin/bash

BASEDIR=$(dirname $BASH_SOURCE)

if [ ! -f fdisk-a.txt ]; then
    echo "ERROR. no fdisk setup files available"
    exit 1
fi

# fdisk. create partition layouts
fdisk /dev/sda < ./fdisk-a.txt
fdisk /dev/sdb < ./fdisk-b.txt

# md
mdadm --create /dev/md0 -n2 -l0 /dev/sda3 /dev/sdb2
mkfs.ext4 -v -E stride=128 /dev/md0

mkdir /z
mount -v /dev/md0 /z

mkfs.ext4 /dev/sda1
mkswap /dev/sda2
mkswap /dev/sdb1

# Mount the boot partition:
cd /z
mkdir boot
mount -v /dev/sda1 boot
