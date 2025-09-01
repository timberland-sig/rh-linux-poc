#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.
#

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../global_vars.sh
. $DIR/../vm_lib.sh

VMNAME=`basename $PWD`

# if [ ! -f efi.tgz ]; then
# 	echo " error efi.tgz file missing"
# 	exit 1
# fi

if [ ! -f eficonfig/startup.nsh ]; then
	echo " error startup.nsh file missing"
	exit 1
fi

if [ ! -f eficonfig/VConfig.efi ]; then
	echo " error VConfig.efi file missing"
	exit 1
fi

if [ ! -f eficonfig/NvmeOfCli.efi ]; then
	echo " error eficonfig/NvmeOfCli.efi file missing"
	exit 1
fi

if [ -d efi ]; then
	echo " error: efi directory is present"
	exit 1
fi

rm -f efidisk
cp -v efidisk.in efidisk

sudo losetup -D loop1
sudo losetup -P loop1 $PWD/efidisk
sudo mkfs.vfat /dev/loop1p1
sudo losetup -D loop1
sleep 2
mkdir -p efi
sudo mount -t vfat -o loop,offset=1048576 $PWD/efidisk $PWD/efi
# sudo tar xzvf efi.tgz
sudo mkdir -p $PWD/efi/EFI/BOOT
sudo cp -v $PWD/eficonfig/startup.nsh $PWD/efi/EFI/BOOT
sudo cp -v $PWD/eficonfig/NvmeOfCli.efi $PWD/efi/EFI/BOOT
sudo cp -v $PWD/eficonfig/VConfig.efi $PWD/efi/EFI/BOOT
sudo umount $PWD/efi
rmdir efi

echo ""
echo " Create a config attempt with \"./create_attempt.sh\"."
echo ""

$DIR/create_attempt.sh 3

echo ""
echo " Next step is to install and configure the target-vm with \"cd ../target-vm; ./install.sh\""
echo ""
