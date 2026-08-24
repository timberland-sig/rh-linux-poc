#!/bin/bash

set -e

if [ "$(id -u)" -ne 0 ] ; then
    echo "This script must be run as root!" >&2
    exit 1
fi

nvme_disk_path="$1"

if [ -z "$nvme_disk_path" ] ; then
    nvme_pcie_device="$(find /sys/bus/pci/devices -name '*00:08*')"
    if [ -z "$nvme_pcie_device" ] ; then
        echo "No PCIe device on address 0x08!" >&2
        exit 1
    fi
    nvme_disk_path="/dev/$(ls $nvme_pcie_device/nvme)n1"
fi

if grep "$nvme_disk_path" /proc/mounts ; then
    echo "Cannot wipe mounted NVMe namespace!" >&2
    exit 1
fi

echo "Wiping $nvme_disk_path..."
dd if=/dev/zero of="$nvme_disk_path" bs=4k count=1
wipefs -af "$nvme_disk_path"
