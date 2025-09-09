#!/bin/make

.PHONY: install clean wipe-disk

# This does not need a lock file because the virt-install command will refuse
# to run if the guest name 'target-vm' is already in use.
install: disks/boot.qcow2 .build/install.sh anaconda-ks.cfg
	@bash ./new-install.sh

disks/boot.qcow2:
	qemu-img create -f qcow2 disks/boot.qcow2 70G
# There is a potential problem with this and that is that it is
# dependant on SELinux
	chcon -t virt_image_t disks/boot.qcow2

clean:
	-virsh destroy target-vm
	-virsh undefine target-vm
	-rm -f disks/boot.qcow2
