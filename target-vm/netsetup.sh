#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

set -e

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../global_vars.sh
. $DIR/../vm_lib.sh

VMNAME=`basename $PWD`

if [ $0 -lt 1 ] ; then
    display_netsetup_help2
    exit 1
fi

mkdir -p .build

make .build/tcp.json

mkdir -p $HOME/.ssh
touch $HOME/.ssh/known_hosts
make .build/id_ecdsa        # Make SSH key for password-less login

SSH_TARGET="root@$1"
SSH_KNOWN_HOST_ID="$1"
case "$1" in
    localhost)
        make NAT_TYPE=localhost .build/hosts.txt
        SSH_TARGET="${SSH_TARGET}:5556"
        SSH_KNOWN_HOST_ID="[localhost]:5556"
    ;;
    *)
        make NAT_TYPE=bridged .build/hosts.txt
    ;;
esac
chmod 644 .build/hosts.txt

if ! [ -f .net ] ; then
    ssh-keygen -R "${SSH_KNOWN_HOST_ID}"

    until ssh-copy-id -i .build/id_ecdsa.pub ssh://${SSH_TARGET} 2>/dev/null ; do
        echo "Waiting for SSH connection..."
        sleep 5
    done

    scp -i .build/id_ecdsa -o StrictHostKeyChecking=no .build/{hosts.txt,tcp.json} start-nvme-target.sh remote-netsetup.sh scp://${SSH_TARGET}
    ssh -t -i .build/id_ecdsa ssh://${SSH_TARGET} "\
        . remote-netsetup.sh $TARGET_MAC2 $TARGET_MAC3 \"$TARGET_CIDR2\" \"$TARGET_CIDR3\" && . start-nvme-target.sh"
    touch .net
fi

echo ""
echo "Use \"ssh -i .build/id_ecdsa ssh://${SSH_TARGET}\" to login to the $VMNAME"
echo ""
