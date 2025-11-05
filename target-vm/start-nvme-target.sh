#!/bin/bash

modprobe nvme_fabrics
modprobe nvmet_tcp
nvmetcli restore tcp.json
dmesg | grep nvmet
service firewalld stop
