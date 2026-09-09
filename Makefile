#!/bin/make
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2026 John Meneghini <jmeneghi@redhat.com> All rights reserved.

.PHONY: help
help:
	@echo ""
	@echo "Top-level Makefile - Setup and manage the NVMe/TCP Boot POC environment"
	@echo ""
	@echo "Setup targets:"
	@echo "  install       : runs user, virt, net, edk2_zip"
	@echo "  user          : setup basic user environment"
	@echo "  devel         : setup development environment"
	@echo "  virt          : install qemu-kvm environment"
	@echo "  edk2_zip      : install latest timberland-sig edk2 release"
	@echo "  edk2          : git clone timberland-sig edk2 repo"
	@echo "                : - build and install artifacts in the host-vm directory"
	@echo "  net           : configure network environment"
	@echo "                : - script prompts for \"bridged\" primary interface."
	@echo "                :   Enter \"none\" to skip primary interface reconfiguration."
	@echo "  router        : configure the router (container) acting as a gateway"
	@echo "                : between the host-vm and target-vm"
	@echo ""
	@echo "Other targets:"
	@echo "  status        : show network interfaces, edk2 info, and VM states"
	@echo "  clean         : tear down the router and revert network configuration"
	@echo ""

.PHONY: install 
install:
	./setup.sh install 

.PHONY: user
user:
	./setup.sh user

.PHONY: devel
devel:
	./setup.sh devel

.PHONY: virt
virt:
	./setup.sh virt

.PHONY: edk2_zip
edk2_zip:
	./setup.sh edk2_zip

.PHONY: edk2
edk2:
	./setup.sh edk2

.PHONY: net
net:
	./setup.sh net

.PHONY: router
router:
	./setup.sh router

.PHONY: status
status:
	./status.sh

.PHONY: clean
clean:
	./teardown.sh router
	./teardown.sh net
