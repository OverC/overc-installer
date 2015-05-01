#!/bin/bash

# simple init helper!

if [ ! -d "/mnt" ]; then
    mkdir /mnt
fi

# $1 is the device
dev="sdc"
if [ -n "$1" ]; then
    dev="$1"
fi

echo "Mounting install partition (${dev}2)..."
mount /dev/${dev}2 /mnt
echo "Linking install partition to /inst"
ln -fs /mnt/inst/ /inst
