#!/bin/make
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2025 Michal Rábek <mrabek@redhat.com> All rights reserved.

VMNAME := $(shell basename $$PWD)
DRIVE_CAP ?= 70G
EXTRA_DRIVES ?= 0
QEMU_ARGS ?= ""
VNC_DISPLAY ?=
export VNC_DISPLAY
ISO ?= $(shell source ../vm-lib/common.sh &>/dev/null && find_iso &>/dev/null && echo $$ISO_FILE)

SETUP_SCRIPT := vm.sh

ifneq ($(VNC_DISPLAY),)
    _DISPLAY_ARGS := --vnc
else
    _DISPLAY_ARGS :=
endif

.PHONY: help
help:
	@echo "Target VM Makefile - Build and manage virtual machines"
	@echo ""
	@echo "Available targets:"
	@echo "  help          Show this help message"
	@echo "  iso           Download an OS ISO image for this VM"
	@echo "  start         Start the VM using QEMU. If the boot disk doesn't exist, install first"
	@echo "  auto-start    Automatically install the OS with Kickstart and start the VM (Red Hat distros only)"
	@echo "  enter         Open an SSH connection to the VM in the current terminal window."
	@echo "                ./netsetup.sh MUST be run first! The login is passwordless."
	@echo "  kill          Kill all $(VMNAME) instances"
	@echo "  clean         Remove VM boot disk images and temporary files"
	@echo "  wipe          Delete ALL disk images (including host-vm data and OS)"
	@echo ""
	@echo "Disk creation targets:"
	@echo "  disks/boot.qcow2      Create an empty boot disk image ($(DRIVE_CAP))"
	@echo "  disks/nvme1.qcow2     Create an empty NVMe disk image ($(DRIVE_CAP))"
	@echo "  boot.iso              Create a custom ISO with the embedded Kickstart config"
	@echo ""
	@echo "Configuration variables:"
	@echo "  DRIVE_CAP     Disk capacity (default: $(DRIVE_CAP))"
	@echo "  EXTRA_DRIVES  Number of extra NVMe drives (default: $(EXTRA_DRIVES))"
	@echo "  VNC_DISPLAY   VNC display number (forces VNC mode, e.g., VNC_DISPLAY=0)"
	@echo "  QEMU_ARGS     Additional QEMU arguments"
	@echo "  ISO           Path to a .iso to be used for OS installation"
	@echo ""
	@echo "Examples:"
	@echo "  make start                      # Start the VM (installs if no boot disk)"
	@echo "  make auto-start                 # Start the VM with the auto-installed disk (Red Hat)"
	@echo "  make DRIVE_CAP=100G start       # Start with 100GB disks"
	@echo "  make VNC_DISPLAY=0 start        # Start with VNC on display :0"
	@echo ""

.PHONY: auto-start
.ONESHELL: auto-start
auto-start: disks/nvme1.qcow2 $(SETUP_SCRIPT)
	[ -f disks/boot.qcow2 ] || make auto-install || exit 1
	@bash ./$(SETUP_SCRIPT) start disks/boot.qcow2 $(_DISPLAY_ARGS) -n $(EXTRA_DRIVES) -- $(QEMU_ARGS)

.PHONY: auto-install
auto-install: disks/boot.qcow2 boot.iso $(SETUP_SCRIPT)
	@source ../vm-lib/colors.sh && echo -e "$${RED}The VM is installing. Do not interrupt!$${NC}"
	@bash ./$(SETUP_SCRIPT) install $< -F -i boot.iso -- $(QEMU_ARGS)

.PHONY: start
start: disks/nvme1.qcow2 $(SETUP_SCRIPT)
	[ -f disks/boot.qcow2 ] || make install
	@bash ./$(SETUP_SCRIPT) start disks/boot.qcow2 $(_DISPLAY_ARGS) -i $(ISO) -n $(EXTRA_DRIVES) -- $(QEMU_ARGS)

.PHONY: install
install: iso disks/boot.qcow2
	@bash ./$(SETUP_SCRIPT) install disks/boot.qcow2 $(_DISPLAY_ARGS) -n $(EXTRA_DRIVES) -- $(QEMU_ARGS)

.PHONY: enter
.ONESHELL: enter
.SILENT: enter
enter:
	source ../defaults.sh

	if [ ! -f .ip ] ; then
		echo "./.ip lock file not found!" >&2
		echo "Run ./netsetup.sh" >&2
		exit 1
	fi

	ip_addr="$$(cat $$PWD/.ip)"
	if [ "$$ip_addr" = "localhost" ] ; then
		ip_addr=$${ip_addr}:$${TARGET_PORT}
	fi
	ssh -i $$(realpath $$PWD/../.ssh/id_ecdsa) ssh://root@$${ip_addr}

.PHONY: iso
iso:
	@source ../defaults.sh && export MIRROR_CENTOS MIRROR_FEDORA && python3 ../iso_selector.py

# This file must be re-built every time because it depends on environment variables
.PHONY: .build/tcp.json
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
.ONESHELL: boot.iso
boot.iso: iso anaconda-ks.cfg
# Look up the prebuilt ISO
	if ! [ -f $@ ] ; then
		-sudo mkksiso --ks anaconda-ks.cfg -c "console=ttyS0,115200n8 inst.text" "$(ISO)" $@
	fi

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
	-rm -f disks/boot.qcow2
	-rm -f boot.iso
	-rm -f *.log
	-rm -rf .build
	-rm -f anaconda-ks.cfg
	-rm -f .net*
	-rm -f .ip

.PHONY: is-running
is-running:
	@pgrep -f "[q]emu-system-x86.*$(VMNAME)" > /dev/null && echo "YES" || echo "NO"

# We put q in [] to prevent 'kill' from killing its parent shell process
.PHONY: kill
kill:
	@if [ -n "$$(pgrep -f "[q]emu-system-x86.*$(VMNAME)")" ] ; then \
		kill $$(pgrep -f "[q]emu-system-x86.*$(VMNAME)") ; \
	fi
