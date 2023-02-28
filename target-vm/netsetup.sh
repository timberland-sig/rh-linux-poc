#!/bin/bash
# Copyright (c) John Anthony Meneghini, All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#   Author: John Meneghini <jmeneghi@redhat.com>

VMNAME=`basename $PWD`

display_help() {
  echo " "
  echo " Usage: netsetup.sh <device1> <device2> <ipv4_addr>"
  echo " "
  echo " Creates creates a network configuration script called .build/netsetup.sh for $VMNAME"
  echo " "
  echo "   E.g.:"
  echo "          $0 ens6 ens7 192.168.1.154"
  echo " "
}

create_netsetup() {
	STR="$3"
        SUB1='192.168'
	case $STR in
  		*"$SUB1"*)
			P2=$(echo "$STR" | cut -d '.' -f 4)
			P1=$(echo "$STR" | cut -d '.' -f 1,2)
			;;
		*)
  			echo " "
			echo "$STR is invalid"
			display_help >&2
			exit 1
			;;
	esac

	rm -f .build/netsetup.sh
	echo " "
	echo "creating .build/netsetup.sh"
	cat << EOF >> .build/netsetup.sh
#!/bin/bash

CONN="\$(nmcli conn show)"
CONN2="\$(nmcli dev status)"
WIRE1="$1"
WIRE2="$2"

if [[ "\$CONN" == *"\$WIRE1"* ]]; then
	nmcli con mod "\$WIRE1" ipv4.addresses $P1.101.$P2/24 ipv4.gateway $P1.101.1 ipv4.method manual
	nmcli con up "\$WIRE1"
else 
	if [[ "\$CONN2" == *"\$WIRE1"* ]]; then
		nmcli con add type ethernet con-name \$WIRE1 ifname \$WIRE1 ip4 $P1.101.$P2/24 gw4 $P1.101.1 ipv4.method manual
		nmcli con up "\$WIRE1"
        else
		echo "\$WIRE1 not found"
		exit 1
	fi
fi

if [[ "\$CONN" == *"\$WIRE2"* ]]; then
	nmcli con mod "\$WIRE2" ipv4.addresses $P1.110.$P2/24 ipv4.gateway $P1.110.1 ipv4.method manual
	nmcli con up "\$WIRE2"
else 
	if [[ "\$CONN2" == *"\$WIRE2"* ]]; then
		nmcli con add type ethernet con-name \$WIRE2 ifname \$WIRE2 ip4 $P1.110.$P2/24 gw4 $P1.110.1 ipv4.method manual
		nmcli con up "\$WIRE2"
        else
		echo "\$WIRE2 not found"
		exit 1
	fi
fi

nmcli g hostname $VMNAME

ip -h -c -o -br address show

dnf install -y git tar vim nvmetcli

#dnf install -y nvmetcli
#modprobe nvme_fabrics
#modprobe nvmet_tcp
#nvmetcli restore tcp1.json
#dmesg | grep nvmet
#service firewalld stop

EOF
	chmod 775 .build/netsetup.sh

	rm -f .build/host.txt
	echo " "
	echo "creating .build/host.txt"
	cat << EOF >> .build/host.txt

$STR $VMNAME  
$P1.101.$P2 $VMNAME-l1
$P1.110.$P2 $VMNAME-l2

$(cat hosts.txt)

EOF
	chmod 775 .build/host.txt

}

if [ $# -lt 3 -o $# -gt 3 ] ; then
	display_help
	exit 1
fi

create_netsetup $1 $2 $3

echo ""
echo "scp .build/netsetup.sh root@$3:netsetup.sh"
echo ""

scp .build/netsetup.sh root@$3:netsetup.sh

echo ""
echo "scp .build/host.txt root@$3:host.txt"
echo ""

scp .build/host.txt root@$3:host.txt

