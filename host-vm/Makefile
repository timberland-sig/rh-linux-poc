#!/bin/make
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2025 Michal Rábek <mrabek@redhat.com> All rights reserved.

VMNAME := $(shell basename $$PWD)
DRIVE_CAP ?= 70G
NET_TYPE ?= "localhost"
QEMU_ARGS ?= ""
METHOD ?= auto
INPUT_ISO ?= $(shell source ../vm-lib/common.sh &>/dev/null && find_iso &>/dev/null && echo $$ISO_FILE)

ifeq ($(METHOD),auto)
    ISO ?= boot.iso
else ifeq ($(METHOD),manual)
	ISO = $(INPUT_ISO)
    ifndef ISO
        $(error 'ISO' must contain an ISO file path when METHOD="manual"!)
    endif
else
    $(error 'METHOD' must be either "auto" or "manual!")
endif

SETUP_SCRIPT := vm.sh

.ONESHELL: help
.PHONY: help
help:
	@echo "Host VM Makefile - Manage NVMe/TCP boot test host VM"
	@echo ""
	@echo "Main targets:"
	@echo "  help            Show this help message"
	@echo "  iso             Download an OS ISO image for this VM"
	@echo "  setup           Configure NBFT (NVMe Boot Firmware Table) for network boot"
	@echo "  install-local   Install OS to local boot disk"
	@echo "  start-local     Start VM from local boot disk"
	@echo "  install-remote  Install OS to remote NVMe/TCP disk"
	@echo "  start-remote    Start VM from remote NVMe/TCP disk"
	@echo "  kill            Kill all $(VMNAME) instances"
	@echo "  config          Run the interactive setup of the boot attempt configuration"
	@echo "  reconfig        Re-run the interactive setup of the boot attempt configuration"
	@echo "                  This will NOT overwrite vm_vars.fd! Run 'make setup' again for that."
	@echo "  clean-config    Remove the boot attempt configuration file"
	@echo "  clean           Remove all VM disk images and temporary files"
	@echo ""
	@echo "Disk and configuration targets:"
	@echo "  disks/boot.qcow2      Create an empty boot disk image ($(DRIVE_CAP))"
	@echo "  boot.iso              Create a custom ISO with embedded Kickstart config"
	@echo "  efidisk               Create EFI disk with NBFT configuration (this target is interactive)"
	@echo "  anaconda-ks.cfg       Generate Anaconda kickstart from template"
	@echo ""
	@echo "Configuration variables:"
	@echo "  DRIVE_CAP     Disk capacity (default: $(DRIVE_CAP))"
	@echo "  NET_TYPE      Network type: localhost/bridged (default: $(NET_TYPE))"
	@echo "  QEMU_ARGS     Additional QEMU arguments"
	@echo "  ISO             Path to a .iso to be used for OS installation"
	@echo ""
	@echo "Examples:"
	@echo "  make install-local                  # Install to local disk"
	@echo "  make setup                          # Configure NBFT for network boot"
	@echo "  make install-remote                 # Install to remote NVMe/TCP disk"
	@echo "  make start-remote                   # Boot from remote NVMe/TCP disk"
	@echo "  make DRIVE_CAP=100G install-local   # Install with 100GB disk"
	@echo "  make NET_TYPE=bridged start-local   # Start with bridged networking"
	@echo ""

.PHONY: setup
setup: vm_vars.fd .build/hostid

.PHONY: start-local
start-local: disks/boot.qcow2 $(SETUP_SCRIPT)
	bash ./$(SETUP_SCRIPT) -c $(NET_TYPE) start local -- $(QEMU_ARGS)

.PHONY: install-local
install-local: iso disks/boot.qcow2 $(ISO)
	bash ./$(SETUP_SCRIPT) -c $(NET_TYPE) -i $(ISO) install local -- $(QEMU_ARGS)

.PHONY: install-remote
install-remote: iso $(ISO)
	bash ./$(SETUP_SCRIPT) -c $(NET_TYPE) -i $(ISO) install remote -- $(QEMU_ARGS)

.PHONY: start-remote
start-remote:
	bash ./$(SETUP_SCRIPT) -c $(NET_TYPE) start remote -- $(QEMU_ARGS)

.PHONY: iso
iso:
	@source ../defaults.sh && export MIRROR_CENTOS MIRROR_FEDORA && python3 ../iso_selector.py

disks/%.qcow2:
	mkdir -p disks
	qemu-img create -f qcow2 $@ $(DRIVE_CAP)

.ONESHELL: eficonfig/config
.SILENT: eficonfig/config
eficonfig/config: eficonfig/config.in eficonfig/config2.in
# Copy the skeleton
	cat $< > $@
	source ../defaults.sh
	source ../vm-lib/colors.sh
	source ../vm-lib/common.sh

	sed -i "s/HOSTNQN/$$HOSTNQN/" $@
	sed -i "s/HOSTID/$$HOSTID/" $@
	echo -e "$${YELLOW}host-vm host NQN: $$HOSTNQN$${NC}"
	echo -e "$${YELLOW}host-vm host ID:  $$HOSTID$${NC}"
	echo ""

# Function to configure a boot attempt
	configure_attempt() {
		local num=$$1
		local mac_default=$$2
		local ip_default=$$3
		local target_default=$$4
		local mask_default=$$5
		if [ $$num -gt 1 ]; then
			echo ""
			while true; do
				read -p "Configure boot attempt number $$num? (y/n): " ANSWER
				if [ "$$ANSWER" = "y" ]; then
					break
				elif [ "$$ANSWER" = "n" ]; then
					return 1
				fi
			done
		fi
		echo "=== Configuring Boot Attempt $$num ==="
		if [ "$$num" != "1" ]; then
			cat eficonfig/config2.in >> $@
			sed -i "s/AttemptX/Attempt$$num/" $@
		fi
		if [ -n "$$mac_default" ]; then
			read -p "MAC address (default: $$mac_default): " INPUT_MAC
			INPUT_MAC=$${INPUT_MAC:-$$mac_default}
		else
			read -p "MAC address: " INPUT_MAC
		fi
		sed -i "s/HOST_MAC/$$INPUT_MAC/" $@
		if [ -n "$$ip_default" ]; then
			read -p "Host IP address (default: $$ip_default): " INPUT_IP
			INPUT_IP=$${INPUT_IP:-$$ip_default}
		else
			read -p "Host IP address: " INPUT_IP
		fi
		sed -i "s/HOST_IP/$$INPUT_IP/" $@
		sed -i "s/HOSTGW_IP/0.0.0.0/" $@
		while true; do
			read -p "Subnet mask (CIDR bits 1-31 or dotted decimal, default: $$mask_default): " INPUT_MASK
			INPUT_MASK=$${INPUT_MASK:-$$mask_default}
			if source ../vm-lib/common.sh && validate_subnet_mask "$$INPUT_MASK"; then
				INPUT_MASK=$$(normalize_subnet_mask "$$INPUT_MASK")
				break
			fi
			echo "Error: Invalid subnet mask. Enter CIDR bit count (1-31) or dotted decimal (e.g., 255.255.255.0)."
		done
		sed -i "s/SUBNET_MASK/$$INPUT_MASK/" $@
		if [ -n "$$target_default" ]; then
			read -p "Target IP address (default: $$target_default): " INPUT_TARGET
			INPUT_TARGET=$${INPUT_TARGET:-$$target_default}
		else
			read -p "Target IP address: " INPUT_TARGET
		fi
		sed -i "s/TARGET_IP/$$INPUT_TARGET/" $@
		read -p "Port number (default: 4420): " INPUT_PORT
		INPUT_PORT=$${INPUT_PORT:-4420}
		sed -i "s/TARGET_PORT/$$INPUT_PORT/" $@
		while true; do
			read -p "Use discovery NQN? (y/n): " DISCOVERY
			if [ "$$DISCOVERY" = "y" ]; then
				NQN_VALUE="nqn.2014-08.org.nvmexpress.discovery"
				break
			elif [ "$$DISCOVERY" = "n" ]; then
				read -p "Subsystem NQN (default: $$SUBNQN): " INPUT_NQN
				NQN_VALUE=$${INPUT_NQN:-$$SUBNQN}
				break
			fi
		done
		sed -i "s/SUBNQN/$$NQN_VALUE/" $@
		return 0
	}

# Configure boot attempts
	split_cidr $$TARGET_CIDR2 TARGET_IP2 MASK2
	split_cidr $$TARGET_CIDR3 TARGET_IP3 MASK3
	split_cidr $$HOST_CIDR2   HOST_IP2   MASK
	split_cidr $$HOST_CIDR3   HOST_IP3   MASK

	-configure_attempt 1 "$$HOST_MAC2" "$$HOST_IP2" "$$TARGET_IP2" "$$MASK2" && \
	configure_attempt 2 "$$HOST_MAC3" "$$HOST_IP3" "$$TARGET_IP3" "$$MASK3" && \
	configure_attempt 3 "" "" "" && \
	configure_attempt 4 "" "" ""

	read -p "Connection timeout (default: 3000): " TIMEOUT
	TIMEOUT=$${TIMEOUT:-3000}
	sed -i "s/TIMEOUT/$$TIMEOUT/" $@

	@echo ""
	@echo "EFI Configuration file created successfully"
	@echo ""

# This will likely be deprecated
efidisk: efidisk.in eficonfig/startup.nsh eficonfig/VConfig.efi eficonfig/NvmeOfCli.efi eficonfig/config
	-[ -d efi ] && rmdir efi
# This ensures the target execution can be interrupted
	set -e
	cp -v efidisk.in efidisk

	sudo losetup -D loop1
	sudo losetup -P loop1 $$PWD/efidisk
	sudo mkfs.vfat /dev/loop1p1
	sudo losetup -D loop1

	mkdir -p efi
	sudo mount -t vfat -o loop,offset=1048576 $$PWD/efidisk $$PWD/efi
	sudo mkdir -p $$PWD/efi/EFI/BOOT
	sudo cp -v $$PWD/eficonfig/startup.nsh $$PWD/efi/EFI/BOOT
	sudo cp -v $$PWD/eficonfig/NvmeOfCli.efi $$PWD/efi/EFI/BOOT
	sudo cp -v $$PWD/eficonfig/VConfig.efi $$PWD/efi/EFI/BOOT
	sudo cp -v $$PWD/eficonfig/config $$PWD/efi/EFI/BOOT
	sudo umount $$PWD/efi
	rmdir efi

.PHONY: vm_vars.fd
vm_vars.fd: eficonfig/config nvmeof-utils/ovmf_vars_set
	cp ../ISO/OVMF_VARS.fd $@
	./nvmeof-utils/ovmf_vars_set $@ $<

nvmeof-utils/ovmf_vars_set: nvmeof-utils/ovmf_vars_set.c
	make -C $$(dirname $@)

.ONESHELL: .build/hostid
.build/hostid: ../defaults.sh
	source $<
	mkdir -p .build
	echo "$$HOSTID" > $@

# Simply embed the anaconda kickstart file into the ISO
.ONESHELL: boot.iso
boot.iso: iso anaconda-ks.cfg ../vm-lib/common.sh
	if ! [ -f $@ ] ; then
		sudo mkksiso --ks anaconda-ks.cfg $(INPUT_ISO) $@
	fi

anaconda-ks.cfg: anaconda-ks.cfg.template
	@read -p "Enter a root password for the host-vm: " -s PASSWORD; echo; sed -e "s|<ROOT_PASSWD>|$$(openssl passwd -1 -stdin <<< $$PASSWORD)|" $< > $@

.PHONY: clean-config
clean-config:
	-rm -f eficonfig/config

.PHONY: reconfig
reconfig: clean-config eficonfig/config

.PHONY: config
config: reconfig

.PHONY: clean
clean: clean-config
	-rm -f disks/*.qcow2
	-rm -f boot.iso
	-rm -f *.log
	-rm -rf .build
	-rm -f .net*
	-rm -f anaconda-ks.cfg
	-rm -f efidisk
	-rm -f bootlog

.PHONY: is-running
is-running:
	@pgrep -f "[q]emu-system-x86.*$(VMNAME)" > /dev/null && echo "YES" || { echo "NO"; exit 1; }

# We put q in [] to prevent 'kill' from killing its parent shell process
.PHONY: kill
kill:
	@if [ -n "$$(pgrep -f "[q]emu-system-x86.*$(VMNAME)")" ] ; then \
		kill $$(pgrep -f "[q]emu-system-x86.*$(VMNAME)") ; \
	fi

