#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.
#

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../vm_lib.sh

VMNAME=`basename $PWD`

#These are the Hostnqn and Hostid for the target-vm
TARGETID="e1df2843-7f74-48c4-adb0-b2a5b9bab8f1"
TARGETNQN="nqn.2014-08.org.nvmexpress:uuid:a53caec2-eb2d-4bca-819e-f2bbfb10e1fa"
#These are the Hostnqn and Hostid for the host-vm
HOSTID="4e16bbb4-097f-44be-8c7f-77d8b4fc9f39"
#This HostNQN appears in the tcp.json file
HOSTNQN="nqn.2014-08.org.nvmexpress:uuid:f8131bac-cdef-4165-866b-5998c1e67890"
#This is the Subsystem NQN for the tcp.json file
SUBNQN="nqn.2014-08.org.nvmexpress:uuid:0c468c4d-a385-47e0-8299-6e95051277db"
NSNGUID="ace42e00-1510-2fce-2ee4-ac0000000001"
NSUUID="bee9c2b7-1761-44b5-a4e6-0f690498a94b"

add_host_netsetup() {
    cat << EOF >> .build/netsetup.sh

dnf copr enable -y johnmeneghini/timberland-sig
dnf install -y git tar vim nvme-cli
dnf update -y dracut

echo "$HOSTNQN" > /etc/nvme/hostnqn
echo "$HOSTID" > /etc/nvme/hostid

modprobe nvme_fabrics
modprobe nvme_tcp

EOF
}

check_netsetup_args $#

create_netsetup "$1" "$2" "$3"

add_host_netsetup

create_hosts_file "$3"

chmod 775 .build/netsetup.sh
chmod 775 .build/hosts.txt

echo ""
echo " scp  .build/{netsetup.sh,hosts.txt} root@$3:"
echo ""
scp .build/{netsetup.sh,hosts.txt} root@$3:

echo ""
echo " Login to $VMNAME/root and run \"./netsetup.sh\" to complete the VM configuration"
echo ""

