#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
#
# Renders vm-lib/remote-netsetup.sh.in into a ready-to-run script with all
# per-VM parameters baked in via envsubst, so it can be scp'd to a VM and
# sourced there with no arguments.
#
# Usage: build-remote-netsetup.sh <output-path>
#
# Required environment variables: VMNAME MAC2 MAC3
# Optional environment variables (default empty): IP2 IP3

set -e

DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$DIR/remote-netsetup.sh.in"

OUT="$1"
if [ -z "$OUT" ]; then
    echo "Usage: $0 <output-path>" >&2
    exit 1
fi

for _var in VMNAME MAC2 MAC3; do
    if [ -z "${!_var}" ]; then
        echo "Error: required environment variable $_var is not set" >&2
        exit 1
    fi
done

# Map our plain-named inputs to TPL_*-prefixed envsubst placeholders. The
# template deliberately does *not* reuse these names for its own runtime
# variables (envsubst does a blind whole-file text substitution, so a
# template-side variable sharing a placeholder's name would also get
# clobbered with the raw input value wherever it's referenced later in the
# file, not just at its "declaration" line).
export TPL_VMNAME="$VMNAME" TPL_MAC2="$MAC2" TPL_MAC3="$MAC3"
export TPL_IP2="${IP2:-}" TPL_IP3="${IP3:-}"

# Explicit allow-list: remote-netsetup.sh.in has its own runtime shell
# variables (e.g. $iface, $ip_config, $nbft_match, $uuid, $name) that must
# be left untouched for the VM to evaluate at execution time, instead of
# envsubst blanking them out here (envsubst replaces any *unset* $VAR it's
# allowed to touch with an empty string).
TEMPLATE_VARS='$TPL_VMNAME $TPL_MAC2 $TPL_MAC3 $TPL_IP2 $TPL_IP3'

mkdir -p "$(dirname -- "$OUT")"
envsubst "$TEMPLATE_VARS" < "$TEMPLATE" > "$OUT"
chmod 0755 "$OUT"
