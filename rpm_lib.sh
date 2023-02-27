#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

display_rpm_help() {
  echo " Usage: $0 < srpm | rpm | mock > | < copr repo_name > "
  echo " "
  echo "  srpm - creates a source rpm in $PWD/rpmbulid"
  echo "  rpm  - creates a full rpm in $PWD/rpmbulid"
  echo "  mock - create a source rpm and build it with mock"
  echo "  copr < repo_name > "
  echo "       - create a source rpm and upload it to the copr \"repo_name\" repository"
  echo ""
}

build_copr_pkg() {
	copr-cli build $1 $2
}

check_args() {
    if [ $1 -lt 1 ]; then
        display_rpm_help
        exit 1;
    fi

    MODE=$2

    case "${MODE}" in
           srpm)
           ;;
           rpm)
           ;;
           mock)
           ;;
           copr)
               if [ $1 -lt 2 ]; then
                   display_rpm_help
                   exit 1;
               fi
               COPR_PROJECT=$3
           ;;
           *)
               echo " Invalid argument: $MODE" >&2
               display_rpm_help
               popd
               exit 1
           ;;
    esac
}
