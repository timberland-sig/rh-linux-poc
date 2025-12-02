#!/bin/bash

set -e

modprobe nvme_fabrics
modprobe nvmet_tcp
nvmetcli restore /usr/local/etc/tcp.json

# Configure firewall to allow NVMe/TCP traffic (port 4420) on all zones
systemctl start firewalld
for zone in $(firewall-cmd --get-active-zones | grep -v '^\s' | cut -d' ' -f1); do
    firewall-cmd --zone=$zone --add-port=4420/tcp
done
