#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

set -e

DIR="$(dirname -- "$(realpath -- "$0")")"
echo "$DIR"
. $DIR/../global_vars.sh
. $DIR/../vm-lib/common.sh

VMNAME=`basename $PWD`

if [ $# -lt 1 ] ; then
    echo " "
    echo " Usage: netsetup.sh <ipaddr | localhost>"
    echo " "
    echo " Configures the network of $VMNAME"
    echo " "
    echo "  ipaddr - dhcp assigned ipv4 address of $VMNAME"
    echo "           - corresponds to br0 on the hypervisor host"
    echo ""
    echo "   Passing \"localhost\" in the ipaddr field is used with there is no br0 interface"
    echo "   configured on the hypervisor. See \"./install.sh\" help for more information."
    echo ""
    echo "   E.g.:"
    echo "          $0 192.168.0.63"
    echo "          $0 10.16.188.66"
    echo "          $0 localhost"
    echo " "
    exit 1
fi

case "$VMNAME" in
    target-vm)
        SSH_PORT=$TARGET_PORT
    ;;
    host-vm)
        SSH_PORT=$HOST_PORT
    ;;
    *)
        echo "VM named $VMNAME is not recognized!" >&2
        exit 1
    ;;
esac

mkdir -p .build

mkdir -p $HOME/.ssh
touch $HOME/.ssh/known_hosts

SSH_TARGET="root@$1"
SSH_KNOWN_HOST_ID="$1"
case "$1" in
    localhost)
        make --makefile="$DIR/Makefile" NET_TYPE=localhost .build/hosts.txt
        SSH_TARGET="${SSH_TARGET}:$SSH_PORT"
        SSH_KNOWN_HOST_ID="[localhost]:$SSH_PORT"
    ;;
    *)
        make --makefile="$DIR/Makefile" NET_TYPE=bridged .build/hosts.txt
    ;;
esac
chmod 644 .build/hosts.txt

if ! [ -f .net ] ; then
    ssh-keygen -R "${SSH_KNOWN_HOST_ID}"

    until ssh-copy-id -i $DIR/../.ssh/id_ecdsa.pub ssh://${SSH_TARGET} ; do
        echo "Waiting for SSH connection..."
        sleep 5
    done

    case "$VMNAME" in
        target-vm)
            make --makefile="$PWD/Makefile" .build/tcp.json
            scp -i $DIR/../.ssh/id_ecdsa -o StrictHostKeyChecking=no .build/{tcp.json,hosts.txt} $PWD/start-nvme-target.service $PWD/start-nvme-target.sh $DIR/../vm-lib/remote-netsetup.sh scp://${SSH_TARGET}
            ssh -t -i $DIR/../.ssh/id_ecdsa ssh://${SSH_TARGET} "
set -e
. remote-netsetup.sh $TARGET_MAC2 $TARGET_MAC3 \"$TARGET_CIDR2\" \"$TARGET_CIDR3\"
cp start-nvme-target.sh /usr/local/bin
cp start-nvme-target.service /etc/systemd/system/
mkdir -p /usr/local/etc
cp tcp.json /usr/local/etc
systemctl daemon-reload
systemctl enable --now start-nvme-target.service
systemctl status start-nvme-target.service
dmesg | grep nvmet"
        ;;
        host-vm)
            scp -i $DIR/../.ssh/id_ecdsa -o StrictHostKeyChecking=no .build/hosts.txt $DIR/../vm-lib/remote-netsetup.sh scp://${SSH_TARGET}
            ssh -t -i $DIR/../.ssh/id_ecdsa ssh://${SSH_TARGET} "\
                . remote-netsetup.sh $HOST_MAC2 $HOST_MAC3 \"$HOST_CIDR2\" \"$HOST_CIDR3\""
        ;;
        *)
            # This should never be reached
            exit 500
        ;;
    esac
    touch $PWD/.net
fi

echo ""
echo "Use \"ssh -i \$PWD/../.ssh/id_ecdsa ssh://${SSH_TARGET}\" to login to the $VMNAME"
echo ""
