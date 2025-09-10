#!/bin/make

.PHONY: rh-install rh-clean install setup clean wipe-disk

# This does not need a lock file because the virt-install command will refuse
# to run if the guest name 'target-vm' is already in use.
rh-install: disks/boot.qcow2 anaconda-ks.cfg
	@bash ./new-install.sh

disks/boot.qcow2:
	qemu-img create -f qcow2 disks/boot.qcow2 70G
# There is a potential problem with this and that is that it is
# dependant on SELinux
	chcon -t virt_image_t disks/boot.qcow2

rh-clean:
	-virsh destroy target-vm
	-virsh undefine target-vm

install:
	@bash ./install.sh prebuilt localhost

setup: .build/install.sh
	@bash ./netsetup.sh enp0s5 enp0s6 localhost

clean:
	-rm -f disks/boot.qcow2
	-rm -rf .build
