#!/bin/bash

set -e

if [ "$(id -u)" -ne 0 ] ; then
    echo "This script must be run as root!" >&2
    exit 1
fi

nvme_disk_path="$1"

if [ -z "$nvme_disk_path" ] ; then
    # With the QEMU target, the drive is guaranteed to be at PCIe address 0x08
    nvme_pcie_device="$(find /sys/bus/pci/devices -name '*00:08*')"
    if [ -z "$nvme_pcie_device" ] ; then
        echo "No PCIe device on address 0x08!" >&2
        exit 1
    fi
    nvme_disk_path="/dev/$(ls $nvme_pcie_device/nvme)n1"
fi

# Check if the targeted namespace is being used
if grep "$nvme_disk_path" /proc/mounts ; then
    echo "Cannot serve mounted NVMe namespace!"
    exit 1
fi

echo "Exposing $nvme_disk_path..."

modprobe nvme_fabrics
modprobe nvmet_tcp
cp nvmet-mods.conf /etc/modules-load.d/

# Configure firewall to allow NVMe/TCP traffic (port 4420) on all zones
systemctl start firewalld
for zone in $(firewall-cmd --get-active-zones | grep -v '^\s' | cut -d' ' -f1); do
    firewall-cmd --zone=$zone --add-port=4420/tcp --permanent
done

# Backs up the original system nvmet config (if present)
cp /etc/nvmet/config.json /etc/nvmet/.config.json.old
sed "s|DISKPATH|$nvme_disk_path|" tcp.json > /etc/nvmet/config.json

systemctl daemon-reload
systemctl restart firewalld

if systemctl is-active nvmet.service ; then
    systemctl restart nvmet.service
else
    systemctl enable --now nvmet.service
fi

dmesg | grep nvmet