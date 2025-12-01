#!/bin/bash

set -e

modprobe nvme_fabrics
modprobe nvmet_tcp
nvmetcli restore /usr/local/etc/tcp.json
service firewalld stop
