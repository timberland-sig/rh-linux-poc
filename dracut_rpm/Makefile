# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2026 John Meneghini <jmeneghi@redhat.com> All rights reserved.

COPR_PROJECT ?= NBFT

.PHONY: help rpm srpm mock copr clean

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  rpm    - build dracut RPM"
	@echo "  srpm   - build dracut SRPM"
	@echo "  mock   - build dracut with mock"
	@echo "  copr   - build dracut in COPR (COPR_PROJECT=$(COPR_PROJECT))"
	@echo "  clean  - remove build artifacts"
	@echo ""
	@echo "Options:"
	@echo "  COPR_PROJECT - COPR repository name (default: $(COPR_PROJECT))"

rpm:
	./build.sh rpm

srpm:
	./build.sh srpm

mock:
	./build.sh mock

copr:
	./build.sh copr $(COPR_PROJECT)

clean:
	rm -rf mock_build rpmbuild
