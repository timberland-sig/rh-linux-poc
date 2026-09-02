#!/bin/bash

set -e

to_lower() {
    echo "$1" | awk '{print tolower($0)}'
}

mac2iface() {
	local macaddr=$1
    find /sys/class/net -mindepth 1 ! -name lo -execdir sh -c "[ -e {}/device ] || exit 0; MAC=\$(cat {}/address 2>/dev/null); if [ \"\$MAC\" = \"$macaddr\" ]; then echo \"\$(basename {})\"; fi" \;
}

if [ $# -ne 0 -a $# -ne 2 -a $# -ne 4 ] ; then
	echo "Usage: $0 [<mac address 2> <mac address 3>] [<dhcp|ip/prefix 2> <dhcp|ip/prefix 3>]"
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
fi

setup_iface() {
	local iface=$1
	local ip_config=$2

	if [ -z "$iface" ]; then
		return
	fi

	if [ -z "$ip_config" ]; then
		echo "Skipping interface $iface: no IP configuration provided"
	fi

	# If an nbft connection owns this device, leave it alone entirely
	local nbft_match
	nbft_match=$(nmcli -t -g UUID,NAME con show 2>/dev/null | while IFS=: read -r uuid name; do
		case "$name" in nbft*) ;; *) continue ;; esac
		ifname=$(nmcli -g connection.interface-name con show "$uuid" 2>/dev/null) || continue
		if [ "$ifname" = "$iface" ]; then
			echo "yes"
			break
		fi
	done)
	if [ "$nbft_match" = "yes" ]; then
		return
	fi

	# Remove any pre-existing connections on this device
	nmcli -t -g UUID con show 2>/dev/null | while read -r uuid; do
		ifname=$(nmcli -g connection.interface-name con show "$uuid" 2>/dev/null) || continue
		if [ "$ifname" = "$iface" ]; then
			nmcli con delete uuid "$uuid" 2>/dev/null || true
		fi
	done

	if [ "$ip_config" = "dhcp" ]; then
		nmcli con add \
			type ethernet \
			con-name "${iface}-dhcp" \
			ifname "$iface" \
			ipv4.method auto \
			ipv4.dhcp-timeout 30 \
			ipv4.never-default yes \
			ipv4.may-fail no \
			ipv6.method shared \
			connection.autoconnect yes \
			connection.autoconnect-priority 10 \
			connection.autoconnect-retries 2

		nmcli con up "${iface}-dhcp"
	else
		nmcli con add \
			type ethernet \
			con-name "${iface}-static" \
			ifname "$iface" \
			ipv4.addresses "$ip_config" \
			ipv4.method manual \
			ipv4.never-default yes \
			ipv6.method shared \
			connection.autoconnect yes \
			connection.autoconnect-priority 10

		nmcli con up "${iface}-static"
	fi
}

setup_iface "$IF2" "$IP2"
setup_iface "$IF3" "$IP3"

nmcli g hostname $VMNAME

ip -h -c -o -br address show

cat hosts.txt >> /etc/hosts
if [ -f $HOME/hostid ] ; then
	/bin/cp -f hostid /etc/nvme	# 'cp' may be aliased to 'cp -i'
fi


if [[ $(grep EDITOR ~/.bashrc) =~ vim ]] ; then
   echo "$EDITOR"
else
	echo "EDITOR=vim; export EDITOR;" >> ~/.bashrc
	echo "alias ipshow='ip -h -c -o -br address show'" >> ~/.bashrc
	echo "alias ipmac=\"ip -o link show | cut -d ' ' -f 2,20\"" >> ~/.bashrc
	sed -i "s/# %wheel/%wheel/g" /etc/sudoers
fi

dnf install -y nvme-cli nvmetcli libnvme
