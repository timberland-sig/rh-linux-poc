#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

display_rpm_help() {
  echo " Usage: $0 [ srpm | rpm | copr ]"
  echo " "
  echo "  srpm - creates a source rpm in $PWD/rpmbulid"
  echo "  rpm  - creates a full rpm in $PWD/rpmbulid"
  echo "  copr - create a source rpm and upload it to the copr dist-git repository"
  echo ""
}

build_copr_pkg() {
	copr-cli build timberland-sig $1 $2
}

