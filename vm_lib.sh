#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

# NOTE: caller must include global_vars.sh before including this file.

echo "DIR = $DIR"

display_install_help() {
  echo " Usage: install.sh <boot|prebuilt|\"iso_file\"> <bridged|localhost> [\"qemu_args\"] [-n | -f | -r]"
  echo " "
  echo " Creates qcow2 disk files and installs a QEMU VM named $VMNAME"
  echo " in $PWD using the installation ISO provided in <iso_file>."
  echo ""
  echo " Required arguments:"
  echo ""
  echo " The <boot|prebuilt> argument selects the boot iso from the ISO directory"
  echo "   Pass \"boot\" if you are using a private boot.iso (requires lorax_build)"
  echo "     The boot.iso file must be created by runnning \"setup.sh iso\" first."
  echo "   Pass \"prebuilt\" to use the last downloaded ISO"
  echo "   Pass \"the name of the iso file\" to use a specific downloaded ISO"
  echo "     ISOs must be downloaded by runnning \"setup.sh prebuilt\" first."
  echo ""
  echo " The <bridged|localhost> argument sets the QMEU network configuration:"
  echo ""
  echo "   bridged  : uses a QEMU \"netdev bridge\" interface - requires a bridged \"br0\" interface to be configured."
  echo "   localhost : uses a QEMU \"netdev user\" interface - requires no bridged interface to be configured."
  echo ""
  echo " Optional arguments:"
  echo ""
  echo " [\"qemu_args\"] is passed and added to the qemu command line. For example, use \"-vnc: 0\""
  echo " to pass the -vnc argument to command line."
  echo " "
  echo " Note: this install script will destroy and recreate the existing disk image files."
  echo " Be sure to backup or copy any data on the existing qcow2 disks before running \"./install.sh\"."
  echo ""
  echo " [ -r ] : Initialize vm_vars.fd."
  echo " [ -n ] : Re/Create a new target boot disk."
  echo " [ -f ] : Reuse existing disk files and don't run the install script."
  echo ""
  echo "   E.g.:"
  echo "          $0 boot localhost"
  echo "          $0 prebuilt localhost"
  echo "          $0 prebuilt bridged \"-vnc :0\""
  echo "          $0 RHEL-9.5.0-20240717.2-x86_64-dvd1.iso localhost \"-vnc :0\""
  echo "          $0 prebuilt localhost \"-vnc :0 -smp cpus=8 -numa node,cpus=0-3,nodeid=0 -numa node,cpus=4-7,nodeid=1\""
  echo "          $0 prebuilt localhost \"\" -n"
  echo "          $0 boot localhost \"\" -r"
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

create_boot_disk() {
        if [ ! -d disks ]; then
                mkdir disks
        fi

		echo "creating local disk 1 (boot)"
        rm -f disks/boot.qcow2
        qemu-img create -f qcow2 disks/boot.qcow2 70G
}

create_local_disk() {
        if [ ! -d disks ]; then
                mkdir disks
        fi

		echo "creating local disk 2 (nvme1)"
        rm -f disks/nvme1.qcow2
        qemu-img create -f qcow2 disks/nvme1.qcow2 50G
}

create_nbft_disk() {
        if [ ! -d disks ]; then
                mkdir disks
        fi

        echo " creating host-vm nbft disk"
        rm -f disks/nvme2.qcow2
        qemu-img create -f qcow2 disks/nvme2.qcow2 70G
}

check_qargs() {
    if [  -f .qargs ]; then
        QARGS="$(cat .qargs)"
        NUM=$(echo "$QARGS" | cut -d ':' -f 2)
        echo ""
        echo "Connect to console with \"vncviewer $HOST:$NUM\""
    fi
}

check_netport() {
    if ! [ -f .netaddr ]; then
        echo "Error: file .netaddr not found!"
        exit 1
    else
        NETADDR="$(cat .netaddr)"
    fi

    if [ -f .netport ]; then
        NETPORT="$(cat .netport)"
        echo ""
        echo "Use \"ssh -p $NETPORT root@localhost\" to login to the $VMNAME"
        echo ""
    else
        echo ""
        echo "Use \"ssh root@$NETADDR\" to login to the $VMNAME"
        echo ""
    fi
}

check_qemu_command() {
    echo -n "using "
    command -v qemu-system-x86_64
    if [ $? -ne 0 ]; then echo " qemu-system-x86_64 is not installed"; exit 1; fi

    QEMU="$(command -v qemu-system-x86_64)"
    if [[ $QEMU =~ "/usr/local" ]]; then
            BRIDGE_HELPER="/usr/local/libexec/qemu-bridge-helper"
    else
            BRIDGE_HELPER="/usr/libexec/qemu-bridge-helper"
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
    if [ $1 -lt 2 ] ; then
        display_install_help
        exit 1
    fi

#    echo "args 1 = $1, 2 = $2, 3 = $3, 4 = $4"

    if [ -z "$2" ]; then
		eco "No input for iso"
		exit 1
    else
        case "$2" in
		boot)
            ISOVERSION="boot.iso"
            echo "prebuilt iso is $ISOVERSION"
        ;;
        fedora-37)
            ISOVERSION="$ISOVERSION_F37"
            echo "iso is $ISOVERSION"
        ;;
        fedora-42)
            ISOVERSION="$ISOVERSION_F42"
            echo "iso is $ISOVERSION"
		;;
        prebuilt)
            ISOVERSION="$(cat ${DIR}/../.diso)"
            echo "prebuilt iso is $ISOVERSION"
        ;;
        *)
            ISOVERSION="$2"
            echo "prebuilt iso is $ISOVERSION"
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

    rm -f .qargs

    if [ $1 -gt 2 ] ; then
        QARGS="$4"
        echo "using $QARGS"
        echo "$QARGS" > .qargs
    fi

    check_qemu_command

    create_mac_addresses

    if [[ "$VMNAME" == *"host"* ]]; then
        NET_PORT="5555"
        NET_CIDR="10.1.2.15/24"
    else
        NET_PORT="5556"
        NET_CIDR="10.0.2.15/24"
    fi

    rm -f .netport

    case "$3" in
        localhost)
            NET0_NET="-netdev user,id=net0,net=$NET_CIDR,hostfwd=tcp::$NET_PORT-:22"
            NET0_DEV="-device e1000,netdev=net0,addr=4"
            echo "$NET_PORT" > .netport
        ;;
        bridged)
            NET0_NET="-netdev bridge,br=br0,id=net0,helper=$BRIDGE_HELPER"
            NET0_DEV="-device virtio-net-pci,netdev=net0,mac=$MAC1,addr=4"
        ;;
        *)
	    echo " Error: invalid argument $3"
            exit 1
        ;;
    esac

    echo "using $NET0_NET"
    echo "using $NET0_DEV"
}

display_netsetup_help() {
  echo " "
  echo " Usage: netsetup.sh <ifname2> <ifname3> <ipaddr | localhost>"
  echo " "
  echo " Creates creates a network configuration script called .build/netsetup.sh for $VMNAME"
  echo " "
  echo "  ifname2  - second vm network interface device name (e.g. ens6)"
  echo "           - corresponds to virbr1 on the hypervisor host"
  echo "  ifname3  - third vm network interface device name (e.g. ens7)"
  echo "           - corresponds to virbr2 on the hypervisor host"
  echo "  ipaddr - dhcp assigned ipv4 address of $VMNAME"
  echo "           - corresponds to br0 on the hypervisor host"
  echo ""
  echo " These valuse are obtains from \"ip -br address show\" after booting $VMNAME the first time"
  echo ""
  echo "   Passing \"localhost\" in the ipaddr field is used with there is no br0 interface"
  echo "   configured on the hypervisor. See \"./install.sh\" help for more information."
  echo ""
  echo "   E.g.:"
  echo "          $0 enp0s5 enp0s6 192.168.0.63"
  echo "          $0 enp0s5 enp0s6 10.16.188.66"
  echo "          $0 enp0s5 enp0s6 localhost"
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

make_hosts_file() {
    echo " "
    echo " creating .build/hosts.txt"
    cat << EOF >> .build/hosts.txt
$HOSTGW_IP2    host-gw-br2
$HOSTGW_IP3    host-gw-br3
$TARGET_IP2  target-vm-br2
$TARGET_IP3  target-vm-br3
$HOST_IP2   host-vm-br2
$HOST_IP3   host-vm-br3
EOF
}

add_hosts_file_gw_addr() {
    echo " "
    echo " adding host-gw to .build/hosts.txt"
    cat << EOF >> .build/hosts.txt
$TARGET_ADDR    $VMNAME
$HOST_GW_ADDR   host-gw
EOF
}

create_hosts_file() {

    rm -f .build/hosts.txt
    rm -f .netaddr

    make_hosts_file

    TARGET_ADDR="$1"
    echo "$TARGET_ADDR" > .netaddr

    if ! [ "$TARGET_ADDR" == "localhost" ]; then
        HOST_GW_ADDR="$(ip -br address show br0 | sed 's/\s\+/:/g' | cut -d ':' -f 3 | cut -d '/' -f 1)"
        add_hosts_file_gw_addr
    fi
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

if [[ \$(grep EDITOR ~/.bashrc) =~ vim ]] ; then
   echo "\$EDITOR"
else
	echo "EDITOR=vim; export EDITOR;" >> ~/.bashrc
	echo "alias ipshow='ip -h -c -o -br address show'" >> ~/.bashrc
	echo "alias ipmac=\"ip -o link show | cut -d ' ' -f 2,20\"" >> ~/.bashrc
	sed -i "s/# %wheel/%wheel/g" /etc/sudoers
    USR=""
    echo ""
    read -r -p "enter user account name [none] : " USR
	if ! [ -z \$USR ]; then
		usermod -aG wheel \$USR
    fi
fi

EOF
}
