#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2026 Michal Rábek <mrabek@redhat.com> All rights reserved.

# Only use colors if stdout is a terminal
if [ -t 1 ]; then
    RED="\e[31m"
    GREEN="\e[32m"
    YELLOW="\033[1;33m"
    NC="\e[0m"  # No Color
else
    RED=""
    GREEN=""
    YELLOW=""
    NC=""
fi
