#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.
#

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../global_vars.sh
. $DIR/../vm_lib.sh

VMNAME=`basename $PWD`

create_nvme_target_config() {
    rm -f .build/tcp.json
    rm -f .build/start-nvme-target.sh

    cp tcp.json.in .build/tcp.json

    sed -i "s/HOSTNQN/$HOSTNQN/" .build/tcp.json
    sed -i "s/SUBNQN/$SUBNQN/" .build/tcp.json
    sed -i "s/TARGET_IP2/$TARGET_IP2/" .build/tcp.json
    sed -i "s/TARGET_IP3/$TARGET_IP3/" .build/tcp.json
    sed -i "s/NSNGUID/$NSNGUID/" .build/tcp.json
    sed -i "s/NSUUID/$NSUUID/" .build/tcp.json
    sed -i "s/CTRLSN/$SN2/" .build/tcp.json

    cat << EOF >> .build/start-nvme-target.sh
#!/bin/bash
modprobe nvme_fabrics
modprobe nvmet_tcp
nvmetcli restore tcp.json
dmesg | grep nvmet
service firewalld stop
EOF
}

add_target_netsetup() {
    cat << EOF >> .build/netsetup.sh
dnf install -y nvme-cli nvmetcli

echo "$TARGETID" > /etc/nvme/hostid

echo ""
echo " Run \"./start-nvme-target.sh\" to start the NVMe/TCP soft target."
echo " Then run \"host-vm/start.sh\" on the hypervisor to boot the host-vm with NVMe/TCP "
echo ""

EOF
}

check_netsetup_args $#

create_netsetup "$1" "$2" "$3"

add_target_netsetup

create_hosts_file "$3"

create_nvme_target_config

chmod 755 .build/netsetup.sh
chmod 755 .build/start-nvme-target.sh
chmod 755 .build/tcp.json
chmod 755 .build/hosts.txt

echo ""
read -r -p "Enter root passwd for target-vm : " SSHPASS
if [ -z "$SSHPASS" ]; then
    echo "No passwd provided"
    exit 1
fi

case "$3" in
    localhost)
        echo ""
        echo " scp -o StrictHostKeyChecking=no -P 5556 .build/{netsetup.sh,start-nvme-target.sh,hosts.txt,tcp.json} root@localhost:"
        echo ""
        ssh-keygen -R [localhost]:5556
        sshpass -p "$SSHPASS" scp -o StrictHostKeyChecking=no -P 5556 .build/{netsetup.sh,hosts.txt,start-nvme-target.sh,tcp.json} root@localhost:
	sleep 2
	sshpass -e ssh -Y -p 5556 root@localhost "./netsetup.sh none"
	sleep 2
	sshpass -e ssh -Y -p 5556 root@localhost "shutdown --reboot -h now"
        ;;
        *)
        echo ""
        echo " scp .build/{netsetup.sh,hosts.txt,start-nvme-target.sh,tcp.json} root@$3:"
        echo ""
        ssh-keygen -R $3
        sshpass -p "$SSHPASS" scp -o StrictHostKeyChecking=no .build/{netsetup.sh,hosts.txt,start-nvme-target.sh,tcp.json} root@$3:
	sleep 2
	sshpass -e ssh -Y root@$3 "./netsetup.sh none"
	sleep 2
	sshpass -e ssh -Y root@$3 "shutdown --reboot -h now"
        ;;
   esac

echo "Done"
#echo " Login to $VMNAME/root and run \"./netsetup.sh\" to complete the VM configuration"
#echo ""

check_netport
