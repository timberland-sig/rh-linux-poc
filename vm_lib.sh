#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

display_install_help() {
  echo " Usage: install.sh <iso_file> [\"qemu_args\"]"
  echo " "
  echo " Creates qcow2 disk files and installs a QEMU VM named $VMNAME"
  echo " in $PWD using the installation ISO provided in <iso_file>"
  echo " "
  echo " Note: iso_file must be contain the full iso file location"
  echo ""
  echo "   E.g.:"
  echo "          $0 /root/rh-linux-poc/images/boot.iso \"-vnc :0\""
  echo "          $0 /home/jmeneghi/rh-linux-poc/ISO/Fedora-Server-dvd-x86_64-37-1.7.iso \"-vnc :0 -m 1G\""
  echo "          $0 /home/jmeneghi/rh-linux-poc/lorax_results/images/boot.iso"
  echo " "
}

display_mac_help() {
  echo " "
  echo " Error: mac addresss for $VMNAME not found"
  echo " "
  echo " Rename $PWD directory to supported hostname (see hostname.txt)"
  echo " or modify install.sh script to support new hostname."
  echo " "
}

create_mac_addresses() {
        case "$VMNAME" in
                target-vm)
                        MAC1="52:51:01:01:13:01"
                        MAC2="52:52:02:01:14:02"
                        MAC3="52:53:03:01:15:03"
                        ;;
                host-vm)
                        MAC1="53:51:01:01:13:04"
                        MAC2="53:52:02:01:14:05"
                        MAC3="53:53:03:01:15:06"
                        ;;
                *)
						echo "Error: $VMNAME - not found!"
                        display_mac_help >&2
                        exit 1
                        ;;
        esac
}

create_disks() {
        if [ ! -d disks ]; then
                mkdir disks
        fi

        echo "creating disks"
        rm -f disks/boot.qcow2
        rm -f disks/nvme2.qcow2
        qemu-img create -f qcow2 disks/boot.qcow2 50G
        qemu-img create -f qcow2 disks/nvme2.qcow2 50G
}

check_qemu_command() {
    command -v qemu-system-x86_64
    if [ $? -ne 0 ]; then echo "qemu-system-x86_64 is not installed"; exit 1; fi

    QEMU="$(command -v qemu-system-x86_64)"
    if [[ $QEMU =~ "/usr/local" ]]; then
            BRIDGE="/usr/local/libexec/qemu-bridge-helper"
    else
            BRIDGE="/usr/libexec/qemu-bridge-helper"
    fi
}

check_install_args() {
    if [ $1 -lt 1 ] ; then
        display_install_help
        exit 1
    fi

    if [ ! -f $2 ]; then
        echo "iso file $1 not found!"
        exit 1
    fi

    if [ $1 -gt 1 ] ; then
        QARGS="$3"
    fi

    check_qemu_command

    SN1=$(hexdump -vn8 -e'4/4 "%08X" 1 "\n"' /dev/urandom)
    SN2=$(hexdump -vn8 -e'4/4 "%08X" 1 "\n"' /dev/urandom)
}

display_netsetup_help() {
  echo " "
  echo " Usage: netsetup.sh <conn2> <conn3> <ip_addr>"
  echo " "
  echo " Creates creates a network configuration script called .build/netsetup.sh for $VMNAME"
  echo " "
  echo "  conn2  - second vm network device name (e.g. ens5 or \"Wired connection 2\")"
  echo "           - corresponds to virbr1 on the hypervisor host"
  echo "  conn3  - third vm network device name (e.g. ens6 or \"Wired connection 3\""
  echo "           - corresponds to virbr2 on the hypervisor host"
  echo "  ip_addr  - first vm network dhcp assigned address of $VMNAME"
  echo "           - corresponds to br0 on the hypervisor host"
  echo " "
  echo "   E.g.:"
  echo "          $0 \"Wired connection 2\" \"Wired connection 3\" 192.168.0.154"
  echo " "
}

create_ip_gw() {
    IP2GW="192.168.114.01"
    IP3GW="192.168.115.01"
}

create_ip_addresses() {
        case "$VMNAME" in
                target-vm)
						IP2="192.168.114.02/24"
						IP3="192.168.115.03/24"
                        ;;
                host-vm)
						IP2="192.168.114.05/24"
						IP3="192.168.115.06/24"
                        ;;
                *)
						echo "Error: $VMNAME - not found!"
                        display_netsetup_help >&2
                        exit 1
                        ;;
        esac

        create_ip_gw
}

create_host_file() {

	rm -f .build/host.txt

	echo " "
	echo "creating .build/host.txt"

	cat << EOF >> .build/host.txt

target-vm-br2 192.168.114.02
target-vm-br3 192.168.115.03
host-vm-br2 192.168.114.05
host-vm-br3 192.168.115.06

EOF
}

create_netsetup() {

	create_ip_addresses

	rm -f .build/netsetup.sh

	echo " "
	echo "creating .build/netsetup.sh"

	cat << EOF >> .build/netsetup.sh
#!/bin/bash

CONN="\$(nmcli conn show --active)"
CONN2="\$(nmcli dev status)"
WIRE1="$1"
WIRE2="$2"
BR0="$3"

if [[ "\$CONN" == *"\$WIRE1"* ]]; then
	nmcli con mod "\$WIRE1" ipv4.addresses $IP2 ipv4.gateway $IP2GW ipv4.method manual
	nmcli con up "\$WIRE1"
else
	if [[ "\$CONN2" == *"\$WIRE1"* ]]; then
		nmcli con add type ethernet con-name \$WIRE1 ifname \$WIRE1 ip4 $IP2 gw $IP2GW $P1.101.1 ipv4.method manual
		nmcli con up "\$WIRE1"
        else
		echo "\$WIRE1 not found"
		exit 1
	fi
fi

if [[ "\$CONN" == *"\$WIRE2"* ]]; then
	nmcli con mod "\$WIRE2" ipv4.addresses $IP3 ipv4.gateway $IP3GW ipv4.method manual
	nmcli con up "\$WIRE2"
else
	if [[ "\$CONN2" == *"\$WIRE2"* ]]; then
		nmcli con add type ethernet con-name \$WIRE2 ifname \$WIRE2 ip4 $IP3 gw4 $IP3GW ipv4.method manual
		nmcli con up "\$WIRE2"
        else
		echo "\$WIRE2 not found"
		exit 1
	fi
fi

nmcli g hostname $VMNAME

ip -h -c -o -br address show

EOF
}
