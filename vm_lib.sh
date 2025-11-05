#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

# NOTE: caller must include global_vars.sh before including this file.

echo "DIR = $DIR"

check_qargs() {
    if [  -f .qargs ]; then
        QARGS="$(cat .qargs)"
        NUM=$(echo "$QARGS" | cut -d ':' -f 2)
        echo ""
        echo "Connect to console with \"vncviewer $HOST:$NUM\""
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

find_iso() {
    ISOVERSION="$(cat ../.diso)"
    ISO_FILE=$(find ../ -name $ISOVERSION -print)
    if [ -z "$ISO_FILE" ]; then
	echo " Error: $ISOVERSION not found"
	echo " run \"setup.sh -m iso\" or \"setup.sh prebuilt\""
	exit 1
    else
        ISO_FILE=$(realpath $ISO_FILE)
        echo "using $ISO_FILE"
    fi
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

create_hosts_file() {

    rm -f .build/hosts.txt
    rm -f .netaddr

    echo " "
    echo " creating .build/hosts.txt"
    cat << EOF >> .build/hosts.txt
$HOSTGW_IP2    host-gw-br2
$HOSTGW_IP3    host-gw-br3
$TARGET_IP2    target-vm-br2
$TARGET_IP3    target-vm-br3
$HOST_IP2      host-vm-br2
$HOST_IP3      host-vm-br3
EOF

    TARGET_ADDR="$1"
    if ! [ "$TARGET_ADDR" == "localhost" ]; then
        HOST_GW_ADDR="$(ip -br address show br0 | sed 's/\s\+/:/g' | cut -d ':' -f 3 | cut -d '/' -f 1)"
            echo " "
            echo " adding host-gw to .build/hosts.txt"
            cat << EOF >> .build/hosts.txt
$TARGET_ADDR    $VMNAME
$HOST_GW_ADDR   host-gw
EOF
    fi
}

create_netsetup() {
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

dnf install -y nvme-cli nvmetcli && echo "$TARGETID" > /etc/nvme/hostid
EOF
}

generate_serial_number() {
    hexdump -vn8 -e'4/4 "%08X" 1 "\n"' /dev/urandom
}
