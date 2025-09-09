#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.
#

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../global_vars.sh
. $DIR/../vm_lib.sh

VMNAME=`basename $PWD`
TESTUSR="$USER"
HOSTEFIDIR="$PWD"

add_host_netsetup() {
    cat << EOF >> .build/netsetup.sh
dnf install -y nvme-cli libnvme
echo "$HOSTID" > /etc/nvme/hostid
echo ""
echo " The setup is finished now. Enjoy using your test environment!"
echo ""
EOF
}

create_discover_target() {
    rm -f discover_target.sh
    cat << EOF >> discover_target.sh
#!/bin/bash
sudo modprobe nvme_fabrics
sudo modprobe nvme_tcp
sudo nvme discover --hostnqn=$HOSTNQN --transport=tcp --traddr=$TARGET_IP2 --trsvcid=4420
sudo nvme discover --hostnqn=$HOSTNQN --transport=tcp --traddr=$TARGET_IP3 --trsvcid=4420
EOF
}

check_netsetup_args $#

rm -f discover_target.sh
rm -f .build/netsetup.sh
rm -f .build/hosts.txt

create_netsetup "$1" "$2" "$3"
add_host_netsetup
create_hosts_file "$3"
create_discover_target

chmod 755 discover_target.sh
chmod 755 .build/netsetup.sh
chmod 755 .build/hosts.txt

check_netport

case "$3" in
    localhost)
        echo ""
        echo " scp -P 5555 .build/{netsetup.sh,hosts.txt} root@localhost:"
        echo ""
        ssh-keygen -R [localhost]:5555
        scp -o StrictHostKeyChecking=no -P 5555 .build/{netsetup.sh,hosts.txt} root@localhost:
        ;;
        *)
        echo ""
        echo " scp .build/{netsetup.sh,hosts.txt} root@$3:"
        echo ""
        ssh-keygen -R $3
        scp -o StrictHostKeyChecking=no .build/{netsetup.sh,hosts.txt} root@$3:
        ;;
   esac

echo ""
echo " Login to $VMNAME/root and run \"./netsetup.sh\" to complete the VM configuration."
echo " Then shutdown the host-vm and run the \"./create_efidisk.sh\" command."
echo " You must run \"./start.sh attempt\" to program the efi boot attempts before you can boot remotely."
echo ""
