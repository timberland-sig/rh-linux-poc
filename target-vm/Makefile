#!/bin/make
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2025 Michal Rábek <mrabek@redhat.com> All rights reserved.

VMNAME := $(shell basename $$PWD)
DRIVE_CAP ?= 70G
EXTRA_DRIVES ?= 0
NET_TYPE ?= "localhost"
QEMU_ARGS ?= ""

SETUP_SCRIPT := vm.sh

help:
	@echo "Target VM Makefile - Build and manage virtual machines"
	@echo ""
	@echo "Available targets:"
	@echo "  help          Show this help message"
	@echo "  install       Manually install an OS from an ISO onto a fresh boot disk using QEMU"
	@echo "  start         Start the VM with an existing boot disk using QEMU"
	@echo "  rh-start      Automatically install the OS with Kickstart and start the VM (Red Hat distros only)"
	@echo "  clean         Remove all VM disk images and temporary files"
	@echo ""
	@echo "Disk creation targets:"
	@echo "  disks/boot.qcow2      Create an empty boot disk image ($(DRIVE_CAP))"
	@echo "  disks/nvme1.qcow2     Create an empty NVMe disk image ($(DRIVE_CAP))"
	@echo "  disks/rh-boot.qcow2   Build a pre-installed disk image using livemedia-creator (Red Hat distros only)"
	@echo "  boot.iso              Create a custom ISO with the embedded Kickstart config"
	@echo ""
	@echo "Configuration variables:"
	@echo "  DRIVE_CAP     Disk capacity (default: $(DRIVE_CAP))"
	@echo "  EXTRA_DRIVES  Number of extra NVMe drives (default: $(EXTRA_DRIVES))"
	@echo "  NET_TYPE      Network type: localhost/bridged (default: $(NET_TYPE))"
	@echo "  QEMU_ARGS     Additional QEMU arguments"
	@echo ""
	@echo "Examples:"
	@echo "  make install                    # Manually install an OS on a fresh disk"
	@echo "  make start                      # Start the VM with an existing disk"
	@echo "  make rh-start                   # Start the VM with the auto-installed disk (Red Hat)"
	@echo "  make DRIVE_CAP=100G install     # Install with 100GB disks"
	@echo "  make NET_TYPE=bridged start     # Start with bridged networking"
	@echo ""

rh-start: disks/nvme1.qcow2 $(SETUP_SCRIPT)
# disks/rh-boot.qcow2 is not an explicit dependency because it consumes
# .build/rh-boot.qcow2 for its creation. This, however, confuses GNU Make
# to go rebuild the qcow2 disk unnecessarily.
	[ -f disks/rh-boot.qcow2 ] || make disks/rh-boot.qcow2
	@bash ./$(SETUP_SCRIPT) start disks/rh-boot.qcow2 $(NET_TYPE) $(EXTRA_DRIVES) $(QEMU_ARGS)

	@echo "Record the host interface name and ip address with \"ip -br address show\" command."
	@echo ""
	@echo "If your $(VMNAME) is freshly installed, the next step will be to run the \"./netsetup.sh\" script."
	@echo ""

start: disks/boot.qcow2 disks/nvme1.qcow2 $(SETUP_SCRIPT)
	@bash ./$(SETUP_SCRIPT) start $< $(NET_TYPE) $(EXTRA_DRIVES) $(QEMU_ARGS)

install: disks/boot.qcow2
	@bash ./$(SETUP_SCRIPT) install $< $(NET_TYPE) $(EXTRA_DRIVES) $(QEMU_ARGS)

.build/rh-boot.qcow2: anaconda-ks.cfg
	-@sudo rmdir .build 2>/dev/null
# Look up the prebuilt ISO
	@echo -e "\e[31mThe VM is installing in the background. Do not interrupt!\e[0m"
	source ../vm_lib.sh && find_iso && sudo livemedia-creator \
		--virt-uefi \
		--make-disk --qcow2 \
		--iso=$$ISO_FILE --ks=$< \
		--image-name=$$(basename $@) \
		--resultdir ./.build --arch x86_64 \
		--vnc "sdl"
	sudo chown $$USER:$$USER .build

disks/rh-boot.qcow2: .build/rh-boot.qcow2
	sudo mv .build/rh-boot.qcow2 $@
	sudo chown $$USER:$$USER $@

disks/%.qcow2:
	mkdir -p disks
	qemu-img create -f qcow2 $@ $(DRIVE_CAP)

# Simply embed the anaconda kickstart file into the ISO
boot.iso: anaconda-ks.cfg ../vm_lib.sh
# Look up the prebuilt ISO
	source ../vm_lib.sh && find_iso && sudo mkksiso --ks $< $$ISO_FILE $@

anaconda-ks.cfg: anaconda-ks.cfg.template
	@read -p "Enter a root password for the target-vm: " -s PASSWORD; echo; sed -e "s|<ROOT_PASSWD>|$$(openssl passwd -1 -stdin <<< $$PASSWORD)|" $< > $@

clean:
	-rm -f disks/*.qcow2
	-rm -f boot.iso
	-rm -f *.log
	-rm -rf .build
	-rm -f .netport
	-rm -f .netaddr
	-rm -f anaconda-ks.cfg

.PHONY: help install start rh-start stop clean
