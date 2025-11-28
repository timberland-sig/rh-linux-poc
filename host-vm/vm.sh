#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

set -e

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../global_vars.sh
. $DIR/../vm-lib/common.sh

VMNAME=`basename $PWD`

help() {
    cat << EOF
Usage: $0 <MODE> <OS_LOCATION> [NET_CONN] [EXTRA_QEMU_ARGS...]
   or: $0 nbft-setup

Launches a QEMU/KVM host VM for NVMe/TCP boot testing.

Modes:
  nbft-setup
      Configure NBFT (NVMe Boot Firmware Table) in UEFI for network boot

  install <local|remote> [localhost|bridged] [EXTRA_QEMU_ARGS...]
      Install OS to local boot disk or remote NVMe/TCP disk

  start <local|remote> [localhost|bridged] [EXTRA_QEMU_ARGS...]
      Start VM from local boot disk or remote NVMe/TCP disk

Network options (default: localhost):
  localhost  - User-mode networking with SSH port forwarding
  bridged    - Bridged networking on br0

Additional arguments:
  Any arguments after NET_CONN are passed directly to QEMU

Examples:
  $0 install local localhost                    # Install to local disk
  $0 install remote bridged                     # Install to remote NVMe/TCP disk
  $0 nbft-setup                                 # Configure NBFT for network boot
  $0 start local localhost -nographic           # Start with extra QEMU args
  $0 start remote localhost     # Boot from remote NVMe/TCP disk
EOF
    return
}

HOST=`hostname`
VMNAME=`basename $PWD`
QEMU=none
BRIDGE_HELPER=none
ISO_FILE=""

_1OLD="$1"
if [ $# -le 0 ] ; then
    help
    exit 1
elif [ $# -eq 1 -a \( "$1" = "-h" -o "$1" = "--help" \) ] ; then
    help
    exit 1
elif [ $1 = "nbft-setup" ] ; then
    # We shall assume the efidisk exists
    EFI_DISK="-drive file=efidisk,format=raw,if=none,id=NVME1 -device nvme,drive=NVME1,serial=$SN3"
    MODE="install"
    shift 1
elif [ $# -ge 2 ] ; then
    MODE="$1"
    if [ "$MODE" != "install" -a "$MODE" != "start" ] ; then
        echo "Error: MODE must be 'install' or 'start'"
        exit 1
    fi
    OS_LOCATION="$2"
    if [ "$2" != "local" -a "$2" != "remote" ] ; then
        echo "Error: OS_LOCATION must be 'local' or 'remote'"
        exit 1
    fi
    shift 2
else
    echo "Invalid arguments!"
fi

NET_CONN="${1:-localhost}"
case "$NET_CONN" in
    localhost)
        # NET0_NET="-netdev user,id=net0,net=$NET_CIDR,hostfwd=tcp::$NET_PORT-:22"
        NET0_NET="-netdev user,id=net0,hostfwd=tcp::$HOST_PORT-:22"
        NET0_DEV="-device e1000,netdev=net0,addr=4"
        shift 1
    ;;
    bridged)
        NET0_NET="-netdev bridge,br=br0,id=net0,helper=$BRIDGE_HELPER"
        NET0_DEV="-device virtio-net-pci,netdev=net0,mac=$HOST_MAC1,addr=4"
        shift 1
    ;;
    *)
        echo " Error: invalid argument $NET_CONN"
        exit 1
    ;;
esac

# Collect any extra arguments passed after the network connection parameter
QARGS="$@"

# Only find ISO for 'install' mode
if [[ "$MODE" == "install" ]]; then
    find_iso
    CDROM="-cdrom $ISO_FILE"
fi

check_qemu_command

if [ ! -f eficonfig/NvmeOfCli.efi ]; then
    echo "Error: $PWD/eficonfig/NvmeOfCli.efi not found!"
    exit 1
fi

if [ ! -f vm_vars.fd ]; then
    echo "Error: $PWD/vm_vars.fd not found!"
    exit 1
fi

if [ ! -f OVMF_CODE.fd ]; then
    echo "Error: $PWD/OVMF_CODE.fd not found!"
    exit 1
fi

# Only look for the boot drive in 'local' mode
if [ "$OS_LOCATION" = "local" ] ; then
    BOOT_DISK="disks/boot.qcow2"
    if [ -f "$BOOT_DISK" ] ; then
        echo "using $BOOT_DISK"
        BOOT_DISK=$(cat << EOF
-device nvme,drive=NVME1,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN4
-drive file=$BOOT_DISK,if=none,id=NVME1
EOF
        )
    else
        echo "Error: '$BOOT_DISK' not found!"
        exit 1
    fi
else
    echo "using a remote drive"
fi

NET1_NET="-netdev bridge,br=virbr1,id=net1,helper=$BRIDGE_HELPER"
NET1_DEV="-device virtio-net-pci,netdev=net1,mac=$HOST_MAC2,addr=5"
NET2_NET="-netdev bridge,br=virbr2,id=net2,helper=$BRIDGE_HELPER"
NET2_DEV="-device virtio-net-pci,netdev=net2,mac=$HOST_MAC3,addr=6"

BOOT_OPTIONS="-boot menu=on,splash-time=2000"

VM_VARS_FLASH="-drive if=pflash,format=raw,file=vm_vars.fd"
if [ "$OS_LOCATION" = "local" ] ; then
    # No need for vm_vars.fd if booting from a local disk
    VM_VARS_FLASH=""
fi

$QEMU -name $VMNAME -M q35 -accel kvm -cpu host -m 4G -smp 4 $QARGS \
-uuid $HOST_SYS_UUID \
$BOOT_OPTIONS \
$CDROM \
$BOOT_DISK \
-device virtio-rng \
-drive if=pflash,format=raw,readonly=on,file=OVMF_CODE.fd \
$VM_VARS_FLASH \
$EFI_DISK \
$NET0_NET \
$NET0_DEV \
$NET1_NET \
$NET1_DEV \
$NET2_NET \
$NET2_DEV &

disown %1

if [[ $_1OLD == "nbft-setup" ]] ; then
    echo ""
    echo " Connect to the \"host-vm\" console and immediately Press ESC to enter the UEFI setup menu."
    echo " - Select Boot Manager and run the EFI Internal Shell."
    echo " - The UEFI Shell will execute the \"startup.nsh\" script and program the NBFT."
    echo " - Press ESC to exit Boot Manager select Reset to reboot the VM."
    echo " - UEFI will automatically boot with NVMe/TCP if possible."
    echo " - Shutdown the VM and restart with "$0 install remote" to install the remote disk with NVMe/TCP."
    echo " - Shutdown the VM and restart with "$0 start remote" to boot with NVMe/TCP."
    echo ""
elif [[ "$MODE" == "install" ]]; then
    if [[ "$OS_LOCATION" == "remote" ]] ; then
        echo ""
        echo " Connect to the \"host-vm\" console and wait for the Anaconda installer to start"
        echo " - The remote nvme-tcp disk should appear in the install menu"
    fi
    echo ""
    echo " Be sure to create the root account with ssh access."
    echo " Reboot to complete the install and login to the root account."
    echo ""
    echo " Record the host interface name and ip address with \"ip -br address show\" command."
    echo ""
    echo " Next step will be to run the \"./netsetup.sh\" script."
    echo ""
elif [[ "$MODE" == "start" ]] ; then
    if [[ "$OS_LOCATION" == "local" ]] ; then
        echo ""
        echo " Allow the VM to boot normally, using the default"
        echo " - UEFI will automatically boot from the local disk without NVMe/TCP."
        echo " - Complete your work updating or modifying the local disk and shutdown."
        echo " - Shutdown the host-vm before starting the target-vm."
        echo " - Start target-vm nvme/tcp target server with \"start_nvme_target.sh\"."
        echo " - Restart the host-vm with "$0 nbft-setup" to program the NBFT and boot with NVMe/TCP."
        echo ""
    else
        echo ""
        echo " Connect to the \"host-vm\" console and immediately Press ESC to enter the UEFI setup menu."
        echo " - Select Reset to reboot the VM."
        echo " - UEFI will automatically boot with NVMe/TCP."
        echo ""
    fi

    HOST_IP1='localhost'
    if [ $NET_CONN = 'bridged' ] ; then
        echo " Record the host interface name and ip address with \"ip -br address show\" command."
        echo ""
        read -p "Enter host interface IP address: " HOST_IP1
    fi
    $DIR/../vm-lib/netsetup.sh "$HOST_IP1"
    echo ""
    echo " The setup is finished now. Enjoy using your test environment!"
fi
