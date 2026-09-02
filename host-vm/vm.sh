#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

set -e

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../defaults.sh
. $DIR/../vm-lib/common.sh

VMNAME=`basename $PWD`

show-help() {
    VM_NAME=$(basename $PWD)
    cat << EOF
Usage: $0 [OPTIONS] MODE [OS_LOCATION] [-- [QARGS]]
   or: $0 [OPTIONS] nbft-setup [-- [QARGS]]

Launches a QEMU/KVM host VM for NVMe/TCP boot testing.

Arguments:
  MODE            Operation mode: 'nbft-setup', 'install', or 'start' (required)
  OS_LOCATION     Boot location: 'local' or 'remote' (required for install/start modes)
  QARGS           Optional extra commands for QEMU (after --)

Options:
  -h, --help              Show this help message and exit
  -i, --iso PATH          Path to the ISO file to use
  --vnc[=DISPLAY]         Use VNC for VM display (optional display number, default: :1)
  --graphical             Use graphical display (X11/Wayland)

Examples:
  $0 nbft-setup                   # Configure NBFT for network boot
  $0 install local                # Install to local disk
  $0 start local                  # Start from local disk
  $0 --vnc start remote                         # Start with VNC on display :1
  $0 --vnc=:2 start remote                      # Start with VNC on display :2
  $0 --graphical start local                    # Start with graphical display
EOF
    return
}

HOST=`hostname`
VMNAME=`basename $PWD`
QEMU=none
BRIDGE_HELPER=none
ISO_FILE=""
QARGS=""
_DISPLAY_ARGS=()

# Parse options using getopt
PARSED=$(getopt --options hi: --longoptions help,iso:,conn-type:,vnc::,graphical --name "$0" -- "$@")
if [ $? -ne 0 ]; then
    echo "Error: Failed to parse arguments"
    echo "Use -h or --help for usage information"
    exit 1
fi

eval set -- "$PARSED"

# Extract options
while true; do
    case "$1" in
        -h|--help)
            show-help
            exit 0
            ;;
        -i|--iso)
            ISO_FILE="$2"
            shift 2
            ;;
        --vnc)
            _DISPLAY_ARGS=(--vnc)
            if [ -n "$2" ]; then
                VNC_DISPLAY="${2#:}"
            fi
            shift 2
            ;;
        --graphical)
            _DISPLAY_ARGS=(--graphical)
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Error: Unexpected option: $1"
            exit 1
            ;;
    esac
done

# Check if MODE argument is provided
if [ $# -lt 1 ]; then
    echo "Error: MODE argument is required"
    echo "Use -h or --help for usage information"
    exit 1
fi

# Parse positional parameters
MODE="$1"
shift 1

# Special handling for nbft-setup mode
_IS_NBFT_SETUP=false
if [ "$MODE" = "nbft-setup" ] ; then
    _IS_NBFT_SETUP=true
    # We shall assume the efidisk exists
    EFI_DISK="-drive file=efidisk,format=raw,if=none,id=NVME1 -device nvme,drive=NVME1,serial=$SN3"
    # Internally treat as install mode
    MODE="install"
else
    # Validate MODE
    if [ "$MODE" != "install" -a "$MODE" != "start" ] ; then
        echo "Error: MODE must be 'nbft-setup', 'install', or 'start'"
        exit 1
    fi

    # For install/start modes, OS_LOCATION is required
    if [ $# -lt 1 ]; then
        echo "Error: OS_LOCATION argument is required for '$MODE' mode"
        echo "Use -h or --help for usage information"
        exit 1
    fi

    OS_LOCATION="$1"
    shift 1

    # Validate OS_LOCATION
    if [ "$OS_LOCATION" != "local" -a "$OS_LOCATION" != "remote" ] ; then
        echo "Error: OS_LOCATION must be 'local' or 'remote'"
        exit 1
    fi
fi

# Remaining arguments are QARGS
QARGS="$@"

# Check QEMU installation and find the bridge helper
check_qemu_command

# Setup network configuration based on the effective network setup
if has_router && [ -n "$(get_bridge_slaves ${BRIDGE0_NAME} 2>/dev/null)" ] ; then
        NET0_NET="-netdev bridge,br=$VIRT_HOST_BRIDGE_NAME0,id=net0,helper=$BRIDGE_HELPER"
        NET0_DEV="-device virtio-net-pci,netdev=net0,mac=$HOST_MAC1,addr=4"
elif [ -n "$(get_bridge_slaves ${BRIDGE0_NAME} 2>/dev/null)" ] ; then
        NET0_NET="-netdev bridge,br=$BRIDGE0_NAME,id=net0,helper=$BRIDGE_HELPER"
        NET0_DEV="-device e1000e,netdev=net0,mac=$HOST_MAC1,addr=4"
else
        NET0_NET="-netdev user,id=net0,hostfwd=tcp::$HOST_PORT-:22"
        NET0_DEV="-device e1000e,netdev=net0,addr=4"
fi

# Only find ISO for 'install' mode
if [[ "$MODE" == "install" ]]; then
    [ -n "$ISO_FILE" ] || find_iso
    CDROM="-cdrom $ISO_FILE"
fi

if [ ! -f eficonfig/NvmeOfCli.efi ]; then
    echo "Error: $PWD/eficonfig/NvmeOfCli.efi not found!"
    exit 1
fi

if [ "$OS_LOCATION" != "local" ] || [ "$LOCAL_HOST_VM_USE_NBFT" = "true" ]; then
    if [ ! -f vm_vars.fd ]; then
        echo "Error: $PWD/vm_vars.fd not found!"
        exit 1
    fi
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
-device nvme,drive=NVME1,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN4 \
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

if has_router ; then
	BRIDGE1_NAME="$VIRT_HOST_BRIDGE_NAME1"
	BRIDGE2_NAME="$VIRT_HOST_BRIDGE_NAME2"
fi

if nmcli dev | grep "$BRIDGE1_NAME" &>/dev/null ; then
	NET1_NET="-netdev bridge,br=$BRIDGE1_NAME,id=net1,helper=$BRIDGE_HELPER"
	NET1_DEV="-device rtl8139,netdev=net1,mac=$HOST_MAC2,addr=5"
fi
if nmcli dev | grep "$BRIDGE2_NAME" &>/dev/null ; then
	NET2_NET="-netdev bridge,br=$BRIDGE2_NAME,id=net2,helper=$BRIDGE_HELPER"
	NET2_DEV="-device rtl8139,netdev=net2,mac=$HOST_MAC3,addr=6"
fi

BOOT_OPTIONS="-boot menu=on,splash-time=2000"

VM_VARS_FLASH="-drive if=pflash,format=raw,file=vm_vars.fd"
if [ "$OS_LOCATION" = "local" ] && [ "$LOCAL_HOST_VM_USE_NBFT" != "true" ] ; then
    VM_VARS_FLASH=""
fi

# Check if -vnc was already specified via QARGS pass-through
_vnc_in_qargs=false
for _qarg in $QARGS; do
    if [ "$_qarg" = "-vnc" ]; then
        _vnc_in_qargs=true
        break
    fi
done

if ! $_vnc_in_qargs; then
    resolve_display_mode "${_DISPLAY_ARGS[@]}"
    if [ "$DISPLAY_MODE" = "vnc" ]; then
        VNC_DISPLAY="${VNC_DISPLAY:-1}"
        QARGS="$QARGS -vnc :${VNC_DISPLAY}"
    fi
fi

mkdir -p $PWD/.build
cat > .build/start-vm.sh << EOF
$QEMU -name $VMNAME -M q35 -accel kvm -cpu host -m 4G -smp 4 $QARGS \\
-uuid $HOST_SYS_UUID \\
$BOOT_OPTIONS \\
$CDROM \\
$BOOT_DISK \\
-debugcon file:bootlog -global isa-debugcon.iobase=0x402 \\
-device virtio-rng \\
-drive if=pflash,format=raw,readonly=on,file=OVMF_CODE.fd \\
$VM_VARS_FLASH \\
$EFI_DISK \\
$NET0_NET \\
$NET0_DEV \\
$NET1_NET \\
$NET1_DEV \\
$NET2_NET \\
$NET2_DEV &

disown %1
EOF

chmod +x .build/start-vm.sh
. .build/start-vm.sh

if [ -n "$VNC_DISPLAY" ]; then
    VNC_PORT=$((5900 + VNC_DISPLAY))
    echo ""
    echo " To connect to the $VMNAME over VNC, run: vncviewer $HOST:$VNC_PORT"
    echo ""
fi

if $_IS_NBFT_SETUP ; then
    echo ""
    echo " Connect to the \"host-vm\" console and immediately Press ESC to enter the UEFI setup menu."
    echo " - Select Boot Manager and run the EFI Internal Shell."
    echo " - The UEFI Shell will execute the \"startup.nsh\" script and program the NBFT."
    echo " - Press ESC to exit Boot Manager select Reset to reboot the VM."
    echo " - UEFI will automatically boot with NVMe/TCP if possible."
    echo ""
fi

if [[ "$MODE" == "install" ]]; then
    if [[ "$OS_LOCATION" == "remote" ]] ; then
        echo " Connect to the \"host-vm\" console and wait for the Anaconda installer to start"
        echo " - The remote nvme-tcp disk should appear in the install menu"
	echo ""
    fi
    echo " Be sure to create the root account with ssh access."
    echo " Reboot to complete the install and login to the root account."
    echo ""
    echo " Record the host interface name and ip address with \"ip -br address show\" command."
    echo ""
    echo " Next step will be to run the \"./netsetup.sh\" script."
    echo ""
elif [[ "$MODE" == "start" ]] ; then
    if [[ "$OS_LOCATION" == "local" ]] ; then
        echo " Allow the VM to boot normally, using the default"
        echo " - UEFI will automatically boot from the local disk without NVMe/TCP."
        echo " - Complete your work updating or modifying the local disk and shutdown."
        echo " - Shutdown the host-vm before starting the target-vm."
        echo " - Restart the host-vm with "$0 nbft-setup" to program the NBFT and boot with NVMe/TCP."
        echo ""
    else
        echo " Connect to the \"host-vm\" console and immediately Press ESC to enter the UEFI setup menu."
        echo " - Select Reset to reboot the VM."
        echo " - UEFI will automatically boot with NVMe/TCP."
        echo ""
    fi
fi

echo " The setup is finished now. Enjoy using your test environment!"
echo ""
