#!/bin/bash

set -e

modprobe nvme_fabrics
modprobe nvmet_tcp
service firewalld stop
