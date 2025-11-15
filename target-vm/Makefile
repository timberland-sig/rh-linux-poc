#!/bin/make
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2025 John Meneghini <jmeneghi@redhat.com> All rights reserved.

VMNAME := $(shell basename $$PWD)
ISO ?= "prebuilt"
NET_TYPE ?= "localhost"
QEMU_ARGS ?= ""
START_ARG ?= "nbft"

help:
	@echo "Target VM Makefile - Build and manage virtual machines"
	@echo ""
	@echo "Available targets:"
	@echo "  help          Show this help message"
	@echo "  install       Manually install an OS from an ISO onto a fresh boot disk using QEMU"
	@echo "  setup         Manually configure OS a freshly installed boot disk using QEMU"
	@echo "  start         Start the VM with an existing boot disk using QEMU"
	@echo ""
	@echo "Configuration variables:"
	@echo "  NET_TYPE      Install/Setup: Network type: localhost/bridged (default: $(NET_TYPE))"
	@echo "  ISO           Install: Name of ISO file (default: $(IMAGE_NAME))"
	@echo "  START_ARG     Start argument: local/nbft/multip (default: $(START_ARG))"
	@echo "  QEMU_ARGS     Install: Additional QEMU arguments"
	@echo "  FLAGS         Install: Additional flags"
	@echo ""
	@echo "Examples:"
	@echo "  make install"
	@echo "  make setup"
	@echo "  make start"
	@echo "  make FLAGS=\"-f\" install"
	@echo "  make ISO=RHEL-10.1-20250828.1-x86_64-dvd1.iso install"
	@echo "  make NET_TYPE=bridged QEMU_ARGS=\"-vnc :0\" install"
	@echo "  make NET_TYPE=bridged setup"
	@echo "  make START_ARG=local start"
	@echo "  make START_ARG=multip start"
	@echo ""

install:
ifdef FLAGS
	@bash ./install.sh $(ISO) $(NET_TYPE) "$(QEMU_ARGS)" "$(FLAGS)"
else
	@bash ./install.sh $(ISO) $(NET_TYPE) "$(QEMU_ARGS)"
endif

setup: .build/install.sh
	@bash ./netsetup.sh enp0s5 enp0s6 $(NET_TYPE)

start: .build/start_nbft.sh
	@bash ./start.sh $(START_ARG)

.PHONY: help install start setup
