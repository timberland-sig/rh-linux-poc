#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.
#

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../global_vars.sh
. $DIR/../vm_lib.sh

VMNAME=`basename $PWD`
MODE=0

display_attempt_help() {
  echo " Usage: $0 < 1 | 2 | 3 | 4 | 5 > "
  echo " "
  echo "  1 - simple single attempt "
  echo "  2 - double attempt for mulitpath"
  echo "  3 - double attempt with discovery nqn"
  echo "  4 - double attempt with nid = uuid"
  echo "  5 - double attempt with nid = nguid"
  echo ""
}

config_host() {
sed -i "s/HOSTNQN/$HOSTNQN/" eficonfig/config
sed -i "s/HOSTID/$HOSTID/" eficonfig/config
}

config_target1() {
sed -i "s/HOST_MAC2/$HOST_MAC2/" eficonfig/config
sed -i "s/HOST_IP2/$HOST_IP2/" eficonfig/config
sed -i "s/HOSTGW_IP2/0.0.0.0/" eficonfig/config
sed -i "s/TARGET_IP2/$TARGET_IP2/" eficonfig/config
}

config_target2 () {
sed -i "s/HOST_MAC3/$HOST_MAC3/" eficonfig/config
sed -i "s/HOST_IP3/$HOST_IP3/" eficonfig/config
sed -i "s/HOSTGW_IP3/0.0.0.0/" eficonfig/config
sed -i "s/TARGET_IP3/$TARGET_IP3/" eficonfig/config
}

config_subnqn() {
sed -i "s/SUBNQN/$1/" eficonfig/config
sed -i "s/SUBNQN/$1/" eficonfig/config
}

config_nid() {
sed -i "s/NSNID/$1/" eficonfig/config
sed -i "s/NSNID/$1/" eficonfig/config
}

if [ $# -lt 1 ]; then
	display_attempt_help
	exit 1
fi

MODE=$1

if [ ! -f efidisk ]; then
	echo " error: efidisk file missing"
	exit 1
fi

if [ -d efi ]; then
	echo " error: efi directory is present"
	exit 1
fi

rm -f eficonfig/config

case "${MODE}" in
	   1)
			cp -v eficonfig/config.in eficonfig/config
			config_host
			config_target1
			config_subnqn $SUBNQN 
	   ;;
	   2)
			cp -v eficonfig/config2.in eficonfig/config
			config_host
			config_target1
			config_target2
			config_subnqn $SUBNQN 
	   ;;
	   3)
			cp -v eficonfig/config2.in eficonfig/config
			config_host
			config_target1
			config_target2
			config_subnqn "nqn.2014-08.org.nvmexpress.discovery" 
	   ;;
	   4)
			cp -v eficonfig/config3.in eficonfig/config
			config_host
			config_target1
			config_target2
			config_subnqn $SUBNQN 
			config_nid $NSUUID
	   ;;
	   5)
			cp -v eficonfig/config3.in eficonfig/config
			config_host
			config_target1
			config_target2
			config_subnqn $SUBNQN 
			config_nid $NSNGUID
	   ;;
	   *)
			echo " Invalid argument: $MODE" >&2
			display_attempt_help
			exit 1
	   ;;
esac

mkdir -p efi
sudo mount -t vfat -o loop,offset=1048576 $PWD/efidisk $PWD/efi
sudo cp -f -v $PWD/eficonfig/config $PWD/efi/EFI/BOOT
sudo umount $PWD/efi
rmdir efi

echo ""
echo " config file for attempt $MODE installed"
echo ""
