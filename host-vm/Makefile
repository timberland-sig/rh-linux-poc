#!/bin/make
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2025 Michal Rábek <mrabek@redhat.com> All rights reserved.

VMNAME := $(shell basename $$PWD)
DRIVE_CAP ?= 70G
NET_TYPE ?= "localhost"
QEMU_ARGS ?= ""

SETUP_SCRIPT := vm.sh

help:
	@echo "Host VM Makefile - Manage NVMe/TCP boot test host VM"
	@echo ""
	@echo "Main targets:"
	@echo "  help            Show this help message"
	@echo "  setup           Configure NBFT (NVMe Boot Firmware Table) for network boot"
	@echo "  install-local   Install OS to local boot disk"
	@echo "  start-local     Start VM from local boot disk"
	@echo "  install-remote  Install OS to remote NVMe/TCP disk"
	@echo "  start-remote    Start VM from remote NVMe/TCP disk"
	@echo "  reconfig		 Re-run the interactive setup of the boot attempt configuration"
	@echo "  clean-config	 Remove the boot attempt configuration file"
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
	@echo ""
	@echo "Examples:"
	@echo "  make install-local                  # Install to local disk"
	@echo "  make setup                          # Configure NBFT for network boot"
	@echo "  make install-remote                 # Install to remote NVMe/TCP disk"
	@echo "  make start-remote                   # Boot from remote NVMe/TCP disk"
	@echo "  make DRIVE_CAP=100G install-local   # Install with 100GB disk"
	@echo "  make NET_TYPE=bridged start-local   # Start with bridged networking"
	@echo ""

setup: efidisk
	@bash ./$(SETUP_SCRIPT) nbft-setup $(NET_TYPE) $(QEMU_ARGS)

start-local: disks/boot.qcow2 $(SETUP_SCRIPT)
	@bash ./$(SETUP_SCRIPT) start local $(NET_TYPE) $(QEMU_ARGS)

install-local: disks/boot.qcow2
	@bash ./$(SETUP_SCRIPT) install local $(NET_TYPE) $(QEMU_ARGS)

install-remote:
	@bash ./$(SETUP_SCRIPT) install remote $(NET_TYPE) $(QEMU_ARGS)

start-remote:
	@bash ./$(SETUP_SCRIPT) start remote $(NET_TYPE) $(QEMU_ARGS)

disks/%.qcow2:
	mkdir -p disks
	qemu-img create -f qcow2 $@ $(DRIVE_CAP)

eficonfig/config: eficonfig/config.in eficonfig/config2.in
# Copy the skeleton
	cat $< > $@
	source ../global_vars.sh
	sed -i "s/HOSTNQN/$$HOSTNQN/" $@
	sed -i "s/HOSTID/$$HOSTID/" $@
	sed -i "s/HOST_MAC2/$$HOST_MAC2/" $@
	sed -i "s/HOST_IP2/$$HOST_IP2/" $@
	sed -i "s/HOSTGW_IP2/0.0.0.0/" $@
	sed -i "s/TARGET_IP2/$$TARGET_IP2/" $@

	while true; do
		read -p "Enable multipath? (y/n): " MULTIPATH;
		if [ "$$MULTIPATH" = "y" ]; then
			cat eficonfig/config2.in >> $@;
			sed -i "s/HOST_MAC3/$$HOST_MAC3/" $@;
			sed -i "s/HOST_IP3/$$HOST_IP3/" $@;
			sed -i "s/HOSTGW_IP3/0.0.0.0/" $@;
			sed -i "s/TARGET_IP3/$$TARGET_IP3/" $@;
			break;
		elif [ "$$MULTIPATH" = "n" ]; then
			break;
		fi;
	done

	read -p "Connection timeout (default: 3000): " TIMEOUT
	TIMEOUT=$${TIMEOUT:-3000}
	sed -i "s/TIMEOUT/$$TIMEOUT/" $@;

	while true; do
		read -p "Use discovery NQN? (y/n): " DISCOVERY
		if [ "$$DISCOVERY" = "y" ]; then
			sed -i "s/SUBNQN/nqn.2014-08.org.nvmexpress.discovery/" $@
			sed -i "s/SUBNQN/nqn.2014-08.org.nvmexpress.discovery/" $@
			break
		elif [ "$$DISCOVERY" = "n" ]; then
			sed -i "s/SUBNQN/$$SUBNQN/" $@
			sed -i "s/SUBNQN/$$SUBNQN/" $@
			break
		fi
	done

	while true; do
		echo "1 -> Set NID to NSUUID=$$NSUUID"
		echo "2 -> Set NID to NSNGUID=$$NSNGUID"
		echo "n -> Do not set NID."
		read -p "Set NID? (1/2/n): " NID
		if [ "$$NID" = "1" ]; then
			sed -Ei "/ConnectTimeout:[0-9]+/i\NID:$$NSUUID" $@
			break
		elif [ "$$NID" = "2" ]; then
			sed -Ei "/ConnectTimeout:[0-9]+/i\NID:$$NSNGUID" $@
			break
		elif [ "$$NID" = "n" ]; then
			break
		fi
	done

	@echo ""
	@echo "EFI Configuration file created successfully"
	@echo ""

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

# Simply embed the anaconda kickstart file into the ISO
boot.iso: anaconda-ks.cfg ../vm_lib.sh
# Look up the prebuilt ISO
	source ../vm_lib.sh && find_iso && sudo mkksiso --ks $< $$ISO_FILE $@

anaconda-ks.cfg: anaconda-ks.cfg.template
	@read -p "Enter a root password for the target-vm: " -s PASSWORD; echo; sed -e "s|<ROOT_PASSWD>|$$(openssl passwd -1 -stdin <<< $$PASSWORD)|" $< > $@

clean-config:
	-rm -f eficonfig/config

reconfig: clean-config eficonfig/config

clean: clean-config
	-rm -f disks/*.qcow2
	-rm -f boot.iso
	-rm -f *.log
	-rm -rf .build
	-rm -f .netport
	-rm -f .netaddr
	-rm -f anaconda-ks.cfg
	-rm -f efidisk

.ONESHELL: eficonfig/config
.SILENT: eficonfig/config
.PHONY: help setup install-local start-local install-remote start-remote clean-config reconfig clean
