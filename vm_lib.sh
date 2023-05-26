#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

# NOTE: caller must include global_vars.sh before including this file.

display_host_install_help() {
  echo " Usage: install.sh <\"qemu_args\">"
  echo " "
  echo " Creates qcow2 disk files and installs a QEMU VM named $VMNAME"
  echo " "
  echo " Note: if no qemu argument is needed pass \"\""
  echo ""
  echo "   E.g.:"
  echo "          $0 \"\""
  echo "          $0 \"-vnc :1\""
  echo " "
}

display_install_help() {
  echo " Usage: install.sh <$ISO_VERSION> [\"qemu_args\"]"
  echo " "
  echo " Creates qcow2 disk files and installs a QEMU VM named $VMNAME"
  echo " in $PWD using the installation ISO provided in <iso_file>"
  echo " "
  echo " Note: the <iso_file> must be downloaded with \"setup.sh prebuilt\" first"
  echo " Note: pass \"\" in <iso_file> to use the default lorax_build"
  echo ""
  echo "   E.g.:"
  echo "          $0 \"\""
  echo "          $0 \"\" \"-vnc :0\""
  echo "          $0 fedora-37 \"-vnc :0\""
  echo "          $0 fedora-36"
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
                        MAC1="$TARGET_MAC1"
                        MAC2="$TARGET_MAC2"
                        MAC3="$TARGET_MAC3"
                        ;;
                host-vm)
                        MAC1="$HOST_MAC1"
                        MAC2="$HOST_MAC2"
                        MAC3="$HOST_MAC3"
                        ;;
                *)
			echo " Error: $VMNAME - not found!"
                        display_mac_help >&2
                        exit 1
                        ;;
        esac
}

create_target_disk() {
        if [ ! -d disks ]; then
                mkdir disks
        fi

        echo " creating target-vm disk"
        rm -f disks/boot.qcow2
        qemu-img create -f qcow2 disks/boot.qcow2 50G
}

create_host_disk() {
        if [ ! -d disks ]; then
                mkdir disks
        fi

        echo " creating host-vm disk"
        rm -f disks/nvme2.qcow2
        qemu-img create -f qcow2 disks/nvme2.qcow2 50G
}

check_qargs() {
    if [  -f .qargs ]; then
        QARGS="$(cat .qargs)"
        NUM=$(echo "$QARGS" | cut -d ':' -f 2)
        echo ""
        echo "Connect with \"vncviewer $HOST:$NUM\""
        echo ""
    fi
}

check_qemu_command() {
    command -v qemu-system-x86_64
    if [ $? -ne 0 ]; then echo " qemu-system-x86_64 is not installed"; exit 1; fi

    QEMU="$(command -v qemu-system-x86_64)"
    if [[ $QEMU =~ "/usr/local" ]]; then
            BRIDGE="/usr/local/libexec/qemu-bridge-helper"
    else
            BRIDGE="/usr/libexec/qemu-bridge-helper"
    fi
}

check_host_depends() {
    if [ ! -f eficonfig/NvmeOfCli.efi ]; then
        echo "Error: $PWD/eficonfig/NvmeOfCli.efi not found!"
        exit 1
    fi

    if [ ! -f vm_vars.fd ]; then
        echo "Error: $PWD/vm_vars.fd not found!"
        exit 1
    fi

    if [ ! -f OVMF_CODE.fd ]; then
        echo "Error: $PWD/OVMF_CODE.fd not found!"
        exit 1
    fi
}

check_install_args() {
    if [ $1 -lt 1 ] ; then
        display_install_help
        exit 1
    fi

    if [ -z "$2" ]; then
        ISOVERSION="boot.iso"
    else
        case "$2" in
        fedora-36)
            ISOVERSION="$ISOVERSION_F36"
        ;;
        fedora-37)
            ISOVERSION="$ISOVERSION_F37"
        ;;
        fedora-38)
            ISOVERSION="$ISOVERSION_F38"
        ;;
        *)
	    echo " Error: $2 not found"
            exit 1
        ;;
        esac
    fi

    ISO_FILE=$(find ../ -name $ISOVERSION -print)
    if [ -z "$ISO_FILE" ]; then
	echo " Error: $ISOVERSION not found"
	echo " run \"setup.sh -m iso\" or \"setup.sh prebuilt\""
	exit 1
    else
        ISO_FILE=$(realpath $ISO_FILE)
        echo "using $ISO_FILE"
    fi

    if [ $1 -gt 1 ] ; then
        QARGS="$3"
    fi

    check_qemu_command
}

display_netsetup_help() {
  echo " "
  echo " Usage: netsetup.sh <ifname2> <ifname3> <ipaddr>"
  echo " "
  echo " Creates creates a network configuration script called .build/netsetup.sh for $VMNAME"
  echo " "
  echo "  ifname2  - second vm network interface device name (e.g. ens6)"
  echo "           - corresponds to virbr1 on the hypervisor host"
  echo "  ifname3  - third vm network interface device name (e.g. ens7)"
  echo "           - corresponds to virbr2 on the hypervisor host"
  echo "  ipaddr - dhcp assigned ipv4 address of $VMNAME"
  echo "           - corresponds to br0 on the hypervisor host"
  echo " "
  echo " These valuse are obtains from \"ip -br address show\" after booting $VMNAME the first time"
  echo " "
  echo "   E.g.:"
  echo "          $0 enp0s5 enp0s6 192.168.0.63"
  echo "          $0 enp0s5 enp0s6 10.16.188.66"
  echo " "
}

check_netsetup_args() {
	if [ $1 -lt 3 -o $1 -gt 3 ] ; then
		display_netsetup_help
		exit 1
	fi
}

create_ip_gw() {
    IP2GW="$HOSTGW_CIDR2"
    IP3GW="$HOSTGW_CIDR3"
}

create_ip_addresses() {
        case "$VMNAME" in
                target-vm)
		IP2="$TARGET_CIDR2"
		IP3="$TARGET_CIDR3"
                ;;
                host-vm)
		IP2="$HOST_CIDR2"
		IP3="$HOST_CIDR3"
                ;;
                *)
                echo "Error: $VMNAME - not found!"
                display_netsetup_help >&2
                exit 1
                ;;
        esac
}

create_hosts_file() {

    rm -f .build/hosts.txt

    HOST_GW_ADDR="$(ip -br address show br0 | sed 's/\s\+/:/g' | cut -d ':' -f 3 | cut -d '/' -f 1)"
    TARGET_ADDR="$1"

    echo " "
    echo " creating .build/hosts.txt"

    cat << EOF >> .build/hosts.txt

$HOSTGW_IP2    host-gw-br2
$HOSTGW_IP3    host-gw-br3
$TARGET_IP2  target-vm-br2
$TARGET_IP3  target-vm-br3
$HOST_IP2   host-vm-br2
$HOST_IP3   host-vm-br3

$TARGET_ADDR    $VMNAME
$HOST_GW_ADDR   host-gw

EOF
}

create_netsetup() {

	create_ip_addresses

	rm -f .build/netsetup.sh

	echo " "
	echo " creating .build/netsetup.sh"
	cat << EOF >> .build/netsetup.sh
#!/bin/bash

IF2="$1"
IF3="$2"

CONN="\$(nmcli conn show | grep \$IF2)"
if [[ "\$CONN" == *"\$IF2"* ]]; then
	CCON="\$(nmcli --get-values name,device conn | grep \$IF2 | cut -d ':' -f 1)"
	nmcli con delete "\$CCON"
	nmcli con add type ethernet con-name \$IF2 ifname \$IF2 ipv4.addresses $IP2 ipv4.method manual ipv6.method shared
	nmcli con up "\$IF2"
else
	CONN2="\$(nmcli dev status | grep \$IF2)"
	if [[ "\$CONN2" == *"\$IF2"* ]]; then
			nmcli con add type ethernet con-name \$IF2 ifname \$IF2 ipv4.addresses $IP2 ipv4.method manual ipv6.method shared
			nmcli con up "\$IF2"
	else
			echo "\$IF2 not found"
			exit 1
	fi
fi

CONN="\$(nmcli conn show | grep \$IF3)"
if [[ "\$CONN" == *"\$IF3"* ]]; then
	CCON="\$(nmcli --get-values name,device conn | grep \$IF3 | cut -d ':' -f 1)"
	nmcli con delete "\$CCON"
	nmcli con add type ethernet con-name \$IF3 ifname \$IF3 ipv4.addresses $IP3 ipv4.method manual ipv6.method shared
	nmcli con up "\$IF3"
else
	CONN2="\$(nmcli dev status | grep \$IF3)"
	if [[ "\$CONN2" == *"\$IF3"* ]]; then
		nmcli con add type ethernet con-name \$IF3 ifname \$IF3 ipv4.addresses $IP3 ipv4.method manual ipv6.method shared
		nmcli con up "\$IF3"
	else
		echo "\$IF3 not found"
		exit 1
	fi
fi

nmcli g hostname $VMNAME

ip -h -c -o -br address show

cat hosts.txt >> /etc/hosts

EOF
}
