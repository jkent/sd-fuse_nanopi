#!/bin/bash

# Copyright (C) Guangzhou FriendlyARM Computer Tech. Co., Ltd. 
# (http://www.friendlyarm.com)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, you can access it online at
# http://www.gnu.org/licenses/gpl-2.0.html.

# Automatically re-run script under sudo if not root
if [ $(id -u) -ne 0 ]; then
  echo "Rerunning script under sudo..."
  sudo "$0" "$@"
  exit
fi

# ----------------------------------------------------------
# Prebuilt images and host tool

UBOOT_BIN=./prebuilt/u-boot.bin
KERNELIMG=./prebuilt/zImage
ENV_FILE=./prebuilt/sdenv.raw

SD_FDISK=./prebuilt/sd_fdisk_deb

# ----------------------------------------------------------
# Checking device for fusing

if [ -z $1 ]; then
	echo "Usage: $0 DEVICE [sd]"
	exit 0
fi

case $1 in
/dev/sd[a-z] | /dev/loop0)
	DEV_NAME=`basename $1`
	BLOCK_CNT=`cat /sys/block/${DEV_NAME}/size`;;
*)
	echo "Error: Unsupported SD reader"
	exit 0
esac

if [ ${BLOCK_CNT} -le 0 ]; then
	echo "Error: $1 is inaccessible. Stop fusing now!"
	exit 1
fi

if [ ${BLOCK_CNT} -gt 134217727 ]; then
	echo "Error: $1 size (${BLOCK_CNT}) is too large"
	exit 1
fi

if [ "sd$2" = "sdsd" -o ${BLOCK_CNT} -le 4194303 ]; then
	echo "Card type: SD"
	RSD_BLKCOUNT=0
else
	echo "Card type: SDHC"
	RSD_BLKCOUNT=1024
fi

let BL1_POSITION=${BLOCK_CNT}-${RSD_BLKCOUNT}-16-2
let BL2_POSITION=${BL1_POSITION}-32-512
let ENV_POSITION=${BL1_POSITION}-32
let KERNEL_POSITION=${BL2_POSITION}-12288
#echo ${KERNEL_POSITION}


# ----------------------------------------------------------
# partition card

echo "---------------------------------"
echo "make $1 partition"

# umount all at first
umount /dev/${DEV_NAME}* > /dev/null 2>&1

${SD_FDISK} $1
dd iflag=dsync oflag=dsync if=sd_mbr.dat of=$1
rm sd_mbr.dat


# ----------------------------------------------------------
# Create a u-boot binary for movinand/mmc boot

# padding to 256k u-boot
dd if=/dev/zero bs=1k count=256 status=none | tr "\000" "\377" > u-boot-256k.bin
dd if=${UBOOT_BIN} of=u-boot-256k.bin conv=notrunc status=none

# ----------------------------------------------------------
# Fusing uboot, kernel to card

echo "---------------------------------"
echo "BL2 fusing"
dd if=u-boot-256k.bin of=/dev/${DEV_NAME} bs=512 seek=${BL2_POSITION} count=512

echo "---------------------------------"
echo "BL1 fusing"
dd if=u-boot-256k.bin of=/dev/${DEV_NAME} bs=512 seek=${BL1_POSITION} count=16

# remove generated files
rm u-boot-256k.bin

if [ -f ${ENV_FILE} ]; then
  echo "---------------------------------"
  echo "ENV fusing"
  dd if=${ENV_FILE} of=/dev/${DEV_NAME} bs=512 seek=${ENV_POSITION} count=32
fi

echo "---------------------------------"
echo "zImage fusing"
dd if=${KERNELIMG} of=/dev/${DEV_NAME} bs=512 seek=${KERNEL_POSITION}

sync

#<Message Display>
echo "---------------------------------"
echo "U-boot and kernel image is fused successfully."

sync

partprobe /dev/${DEV_NAME}
if [ $? -ne 0 ]; then
    echo "Re-read the partition table failed."
    exit 1
fi

sleep 1

./mkrootfs.sh /dev/${DEV_NAME}

echo "---------------------------------"
echo "Rootfs is fused successfully."
echo "All done."

