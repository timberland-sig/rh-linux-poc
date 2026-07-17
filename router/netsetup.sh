#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2026 Michal Rábek <mrabek@redhat.com> All rights reserved.

DIR="$(dirname -- "$(realpath -- "$0")")"
VMNAME="router-vm"

. $DIR/../vm-lib/colors.sh
. "$DIR/addresses.sh"

show-help() {
    echo ""
    echo " Usage: netsetup.sh"
    echo ""
    echo " Configures the network of $VMNAME"
    echo ""
    echo " Environment variables:"
    echo "  ROUTER_CIDR2 - Router IP address in CIDR notation (default: empty)"
    echo "  ROUTER_CIDR3 - Router IP address in CIDR notation (default: empty)"
    echo ""
    exit 0
}

RUN="incus exec $VMNAME -- "

	lookup_dev_connection() {
		local dev_name="$1"
		$RUN nmcli --get-values NAME,DEVICE conn show | grep "$dev_name" | cut -d':' -f1
	}

	mac2iface() {
		local macaddr=$1
		$RUN find /sys/class/net -mindepth 1 ! -name lo -execdir sh -c "MAC=\$(cat {}/address 2>/dev/null); if [ \"\$MAC\" = \"$macaddr\" ]; then echo \"\$(basename {})\"; fi" \;
	}


	if ! $RUN command -v nmcli &>/dev/null ; then
		$RUN dnf install -y NetworkManager
		$RUN systemctl enable --now NetworkManager
	fi

	ETH1_CONN="$(lookup_dev_connection eth1)"
ETH2_CONN="$(lookup_dev_connection eth2)"

if [ -n "$ROUTER_CIDR2" ] ; then
	$RUN nmcli conn modify "$ETH1_CONN" ipv4.method manual ipv4.addresses "$ROUTER_CIDR2" ipv6.method shared connection.autoconnect yes
	$RUN nmcli dev reapply "eth1"
fi

if [ -n "$ROUTER_CIDR3" ] ; then
	$RUN nmcli conn modify "$ETH2_CONN" ipv4.method manual ipv4.addresses "$ROUTER_CIDR3" ipv6.method shared connection.autoconnect yes
	$RUN nmcli dev reapply "eth2"
fi

for _role in TARGET HOST; do
	for _n in 1 2 3; do
		_iface_var="${_role}${_n}_IFACE"
		_ip_var="${_role}${_n}_IP"
		_net_var="${_role}${_n}_NET"
		dev_name="${!_iface_var}"
		ip_cidr="${!_ip_var}/${!_net_var#*/}"
		dev_conn="$(lookup_dev_connection $dev_name)"
		echo "Connection: $dev_conn"

		if [ -z "$dev_conn" ] ; then
			$RUN nmcli con add type ethernet con-name "$dev_name" ifname "$dev_name" ipv4.addresses "$ip_cidr" ipv4.method manual ipv6.method shared connection.autoconnect yes
			continue
		else
			$RUN nmcli conn modify "$dev_conn" ipv4.method manual ipv4.addresses "$ip_cidr" ipv6.method shared connection.autoconnect yes
		fi
		$RUN nmcli dev reapply "$dev_name"
	done
done

$RUN dnf install -y vim less

$RUN nmcli g hostname $VMNAME

if ! $RUN bash -c '[[ $(grep EDITOR ~/.bashrc) =~ vim ]]' ; then
	$RUN bash -c 'echo "EDITOR=vim; export EDITOR;" >> ~/.bashrc'
	$RUN bash -c 'echo "alias ipshow='"'"'ip -h -c -o -br address show'"'"'" >> ~/.bashrc'
	$RUN bash -c 'echo "alias ipmac=\"ip -o link show | cut -d '"'"' '"'"' -f 2,20\"" >> ~/.bashrc'
	$RUN sed -i "s/# %wheel/%wheel/g" /etc/sudoers
fi

$RUN ip -h -c -o -br address show

# Firewall setup

$RUN sysctl -w net.ipv4.ip_forward=1

if ! $RUN command -v nft ; then
	$RUN dnf install -y nftables
fi

cat $DIR/nftables.conf | $RUN nft -f -
$RUN bash -c 'nft list ruleset > /etc/sysconfig/nftables.conf'
$RUN systemctl enable --now nftables.service

# DHCP server setup

if ! $RUN command -v kea-dhcp4 ; then
	$RUN dnf install -y kea
fi

echo "DNS: ${DNS_SERVERS}"
envsubst < "$DIR/kea-dhcp4.conf.in" | $RUN bash -c 'cat - > /etc/kea/kea-dhcp4.conf'
$RUN systemctl enable --now kea-dhcp4.service
