#!/bin/make
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2026 Michal Rábek <mrabek@redhat.com> All rights reserved.

VMNAME := router-vm
NET_TYPE ?= "localhost"

.PHONY: help
help:
	@echo "Router VM Makefile - Build and manage Incus containers"
	@echo ""
	@echo "Available targets:"
	@echo "  help          Show this help message"
	@echo "  start         Start the container from a Fedora 44 image"
	@echo "  is-running    Check if the container is running"
	@echo "  enter         Launch a bash shell inside the container"
	@echo "  kill          Kill the $(VMNAME) instance"
	@echo "  wipe          Delete the container along with its data"
	@echo "  clean         Same as wipe, but delete local temporary files too"
	@echo ""

.ONESHELL: start
.PHONY: start
start:
	source ../defaults.sh
	@if incus list | grep $(VMNAME) ; then \
		incus start $(VMNAME) ; \
	else \
		incus launch images:fedora/44/default $(VMNAME) ; \
		incus network attach $$BRIDGE1_NAME $(VMNAME) eth1
		incus network attach $$BRIDGE2_NAME $(VMNAME) eth2

		incus network attach $$VIRT_TARGET_BRIDGE_NAME0 $(VMNAME) virbr_target_0
		incus network attach $$VIRT_TARGET_BRIDGE_NAME1 $(VMNAME) virbr_target_1
		incus network attach $$VIRT_TARGET_BRIDGE_NAME2 $(VMNAME) virbr_target_2

		incus network attach $$VIRT_HOST_BRIDGE_NAME0 $(VMNAME) virbr_host_0
		incus network attach $$VIRT_HOST_BRIDGE_NAME1 $(VMNAME) virbr_host_1
		incus network attach $$VIRT_HOST_BRIDGE_NAME2 $(VMNAME) virbr_host_2
	fi

.PHONY: enter
enter:
	-incus exec $(VMNAME) -- bash

.PHONY: wipe
wipe:
	-incus delete $(VMNAME)
.PHONY: clean
clean:
	-rm -f *.log
	-sed -i '/^TARGET_CIDR[123]=/d;/^HOST_CIDR[123]=/d' ../.env

.PHONY: is-running
.ONESHELL: is-running
.SILENT: is-running
is-running:
	status="$$(incus info router-vm | grep '^Status:' | cut -d' ' -f2)"
	if [ -n "$$status" -a "$$status" = "RUNNING" ] ; then
		echo "YES"
	else
		echo "NO"
	fi

.PHONY: kill
kill:
	-incus stop $(VMNAME)
