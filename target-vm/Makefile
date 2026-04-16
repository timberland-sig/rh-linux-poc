#!/bin/make
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2025 Michal Rábek <mrabek@redhat.com> All rights reserved.

VMNAME := $(shell basename $$PWD)
DRIVE_CAP ?= 70G
EXTRA_DRIVES ?= 0
NET_TYPE ?= "localhost"
QEMU_ARGS ?= ""
ISO ?= $(shell source ../vm-lib/common.sh &>/dev/null && find_iso &>/dev/null && echo $$ISO_FILE)

SETUP_SCRIPT := vm.sh

.PHONY: help
help:
	@echo "Target VM Makefile - Build and manage virtual machines"
	@echo ""
	@echo "Available targets:"
	@echo "  help          Show this help message"
	@echo "  install       Manually install an OS from an ISO onto a fresh boot disk using QEMU"
	@echo "  start         Start the VM with an existing boot disk using QEMU"
	@echo "  rh-start      Automatically install the OS with Kickstart and start the VM (Red Hat distros only)"
	@echo "  kill          Kill all $(VMNAME) instances"
	@echo "  clean         Remove VM boot disk images and temporary files"
	@echo "  wipe          Delete ALL disk images (including host-vm data and OS)"
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
	@echo "  ISO           Path to a .iso to be used for OS installation"
	@echo ""
	@echo "Examples:"
	@echo "  make install                    # Manually install an OS on a fresh disk"
	@echo "  make start                      # Start the VM with an existing disk"
	@echo "  make rh-start                   # Start the VM with the auto-installed disk (Red Hat)"
	@echo "  make DRIVE_CAP=100G install     # Install with 100GB disks"
	@echo "  make NET_TYPE=bridged start     # Start with bridged networking"
	@echo ""

.PHONY: rh-start
rh-start: disks/nvme1.qcow2 boot.iso $(SETUP_SCRIPT)
# disks/rh-boot.qcow2 is not an explicit dependency because it consumes
# .build/rh-boot.qcow2 for its creation. This, however, confuses GNU Make
# to go rebuild the qcow2 disk unnecessarily.
	[ -f disks/rh-boot.qcow2 ] || make rh-install
	@bash ./$(SETUP_SCRIPT) start disks/rh-boot.qcow2 -c $(NET_TYPE) -n $(EXTRA_DRIVES) -- $(QEMU_ARGS)

.PHONY: rh-install
rh-install: disks/rh-boot.qcow2 boot.iso $(SETUP_SCRIPT)
	@source ../vm-lib/colors.sh && echo -e "$${RED}The VM is installing in the background. Do not interrupt!$${NC}"
	@bash ./$(SETUP_SCRIPT) install $< -F -c $(NET_TYPE) -i boot.iso -- $(QEMU_ARGS)

.PHONY: start
start: disks/boot.qcow2 disks/nvme1.qcow2 $(SETUP_SCRIPT)
	@bash ./$(SETUP_SCRIPT) start $< -i $(ISO) -c $(NET_TYPE) -n $(EXTRA_DRIVES) -- $(QEMU_ARGS)

.PHONY: install
install: disks/boot.qcow2
	@bash ./$(SETUP_SCRIPT) install $< -c $(NET_TYPE) -n $(EXTRA_DRIVES) -- $(QEMU_ARGS)

.ONESHELL: .build/tcp.json
.build/tcp.json: tcp.json.in Makefile ../defaults.sh
	@source ../defaults.sh
	@source ../vm-lib/common.sh

	split_cidr $$TARGET_CIDR2 TARGET_IP2 MASK
	split_cidr $$TARGET_CIDR3 TARGET_IP3 MASK

	cp $< $@
	sed -i "s/HOSTNQN/$$HOSTNQN/" $@
	sed -i "s/SUBNQN/$$SUBNQN/" $@
	sed -i "s/TARGET_IP2/$$TARGET_IP2/" $@
	sed -i "s/TARGET_IP3/$$TARGET_IP3/" $@
	sed -i "s/NSNGUID/$$NSNGUID/" $@
	sed -i "s/NSUUID/$$NSUUID/" $@
	sed -i "s/CTRLSN/$$SN2/" $@

disks/%.qcow2:
	mkdir -p disks
	qemu-img create -f qcow2 $@ $(DRIVE_CAP)

# Simply embed the anaconda kickstart file into the ISO
boot.iso: anaconda-ks.cfg
# Look up the prebuilt ISO
	sudo mkksiso --ks $< "$(ISO)" $@

anaconda-ks.cfg: anaconda-ks.cfg.template
	@while true; do \
		read -p "Enter a root password for the target-vm: " -s PASSWORD; echo; \
		read -p "Confirm the root password: " -s PASSWORD_CONFIRM; echo; \
		if [ "$$PASSWORD" = "$$PASSWORD_CONFIRM" ]; then \
			sed -e "s|<ROOT_PASSWD>|$$(openssl passwd -1 -stdin <<< $$PASSWORD)|" $< > $@; \
			break; \
		else \
			echo "Passwords do not match. Please try again."; \
		fi; \
	done

.PHONY: wipe
wipe:
	-rm -f disks/*.qcow2
	-rm -f .net  # Necessary to force a re-run of netsetup when re-installing the OS

.PHONY: clean
clean:
	-rm -f disks/rh-boot.qcow2 disks/boot.qcow2
	-rm -f boot.iso
	-rm -f *.log
	-rm -rf .build
	-rm -f anaconda-ks.cfg
	-rm -f .net*

.PHONY: is-running
is-running:
	@pgrep -f "[q]emu-system-x86.*$(VMNAME)" > /dev/null && echo "YES" || { echo "NO"; exit 1; }

# We put q in [] to prevent 'kill' from killing its parent shell process
.PHONY: kill
kill:
	@if [ -n "$$(pgrep -f "[q]emu-system-x86.*$(VMNAME)")" ] ; then \
		kill $$(pgrep -f "[q]emu-system-x86.*$(VMNAME)") ; \
	fi
