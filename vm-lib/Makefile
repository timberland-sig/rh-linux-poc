#!/bin/make
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2025 Michal Rábek <mrabek@redhat.com> All rights reserved.

NET_TYPE ?= "localhost"

.ssh/id_ecdsa .ssh/id_ecdsa.pub:
	@echo " : generating SSH keys for password-less login to the VMs..."
	mkdir -p .ssh
	ssh-keygen -t ecdsa -C "$$USER@$$HOSTNAME" -f $$PWD/.ssh/id_ecdsa -P ""
	chmod 600 .ssh/id_ecdsa

.build/hosts.txt: Makefile ../defaults.sh
		@source ../defaults.sh
		@source ../vm-lib/common.sh

		split_cidr $$TARGET_CIDR2 TARGET_IP2 MASK
		split_cidr $$TARGET_CIDR3 TARGET_IP3 MASK
		split_cidr $$HOST_CIDR2   HOST_IP2   MASK
		split_cidr $$HOST_CIDR3   HOST_IP3   MASK

		@cat << EOF > $@
	$$HOSTGW_IP2    host-gw-br2
	$$HOSTGW_IP3    host-gw-br3
	$$TARGET_IP2    target-vm-br2
	$$TARGET_IP3    target-vm-br3
	$$HOST_IP2      host-vm-br2
	$$HOST_IP3      host-vm-br3
	EOF

		if [ $(NET_TYPE) = "bridged" ] ; then
			HOST_GW_ADDR="$$(ip -br address show $$BRIDGE0_NAME | sed 's/\s\+/:/g' | cut -d ':' -f 3 | cut -d '/' -f 1)"
			cat << EOF >> $@
	$$HOST_GW_ADDR   host-gw
	EOF
		fi

.ONESHELL: .build/hosts.txt

VMNAME ?=
MAC1 ?=
MAC2 ?=
MAC3 ?=
IP1 ?=
IP2 ?=
IP3 ?=
GATEWAY ?=
ROUTES2 ?=
ROUTES3 ?=
DNS_SERVERS ?=
NBFT_WORKAROUND ?=

# This target's real inputs are driven by the dispatcher's runtime
# has_router/has_dhcpd branching (e.g. switching router-dynamic <->
# router-static without an intervening `make clean`), which can change
# between consecutive invocations without any file timestamp changing -
# declared .PHONY (unlike .build/hosts.txt) so it always re-renders.
.PHONY: .build/remote-netsetup.sh
.build/remote-netsetup.sh: ../vm-lib/remote-netsetup.sh.in ../vm-lib/build-remote-netsetup.sh
		@mkdir -p .build
		@VMNAME="$(VMNAME)" MAC1="$(MAC1)" MAC2="$(MAC2)" MAC3="$(MAC3)" \
		 IP1="$(IP1)" IP2="$(IP2)" IP3="$(IP3)" \
		 GATEWAY="$(GATEWAY)" ROUTES2="$(ROUTES2)" ROUTES3="$(ROUTES3)" \
		 DNS_SERVERS="$(DNS_SERVERS)" NBFT_WORKAROUND="$(NBFT_WORKAROUND)" \
		 ../vm-lib/build-remote-netsetup.sh $@
