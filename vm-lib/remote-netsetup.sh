#!/bin/bash

set -e

to_lower() {
    echo "$1" | awk '{print tolower($0)}'
}

mac2iface() {
    find /sys/class/net -mindepth 1 ! -name lo -execdir sh -c "MAC=\$(cat {}/address 2>/dev/null); if [ \"\$MAC\" = \"$1\" ]; then echo \"\$(basename {})\"; fi" \;
}

if [ $# -ne 4 ] ; then
	echo "Usage: $0 <mac address 2> <mac address 3> <ip address 2> <ip address 3>"
	exit 1
fi

MAC2="$(to_lower \"$1\")"
MAC3="$(to_lower \"$2\")"
IP2="$3"
IP3="$4"

IF2="$(mac2iface \"$MAC2\")"
IF3="$(mac2iface \"$MAC3\")"

echo "<$IF2> <$IF3>"
if [ '(' -z $IF2 ')' -o '(' -z $IF3 ')' ] ; then
    if [ -z "$IF2" ] ; then
        BAD_MAC="$MAC2"
    else
        BAD_MAC="$MAC3"
    fi
    echo "Failed to find a network interface with MAC address $BAD_MAC!"
    exit 1
fi

CONN="$(nmcli conn show | grep $IF2)"
if [[ "$CONN" == *"$IF2"* ]]; then
	CCON="$(nmcli --get-values name,device conn | grep $IF2 | cut -d ':' -f 1)"
	nmcli con delete "$CCON"
	nmcli con add type ethernet con-name $IF2 ifname $IF2 ipv4.addresses $IP2 ipv4.method manual ipv6.method shared
	nmcli con up "$IF2"
else
	CONN2="$(nmcli dev status | grep $IF2)"
	if [[ "$CONN2" == *"$IF2"* ]]; then
			nmcli con add type ethernet con-name $IF2 ifname $IF2 ipv4.addresses $IP2 ipv4.method manual ipv6.method shared
			nmcli con up "$IF2"
	else
			echo "$IF2 not found"
			exit 1
	fi
fi

CONN="$(nmcli conn show | grep $IF3)"
if [[ "$CONN" == *"$IF3"* ]]; then
	CCON="$(nmcli --get-values name,device conn | grep $IF3 | cut -d ':' -f 1)"
	nmcli con delete "$CCON"
	nmcli con add type ethernet con-name $IF3 ifname $IF3 ipv4.addresses $IP3 ipv4.method manual ipv6.method shared
	nmcli con up "$IF3"
else
	CONN2="$(nmcli dev status | grep $IF3)"
	if [[ "$CONN2" == *"$IF3"* ]]; then
		nmcli con add type ethernet con-name $IF3 ifname $IF3 ipv4.addresses $IP3 ipv4.method manual ipv6.method shared
		nmcli con up "$IF3"
	else
		echo "$IF3 not found"
		exit 1
	fi
fi

nmcli g hostname $VMNAME

ip -h -c -o -br address show

cat hosts.txt >> /etc/hosts

if [[ $(grep EDITOR ~/.bashrc) =~ vim ]] ; then
   echo "$EDITOR"
else
	echo "EDITOR=vim; export EDITOR;" >> ~/.bashrc
	echo "alias ipshow='ip -h -c -o -br address show'" >> ~/.bashrc
	echo "alias ipmac=\"ip -o link show | cut -d ' ' -f 2,20\"" >> ~/.bashrc
	sed -i "s/# %wheel/%wheel/g" /etc/sudoers
fi

dnf install -y nvme-cli nvmetcli libnvme && echo "$TARGETID" > /etc/nvme/hostid
