#!/bin/bash
/usr/bin/qemu-system-x86_64 -name target-vm -M q35 -accel kvm -bios OVMF-pure-efi.fd -cpu host,migratable=on \
	-m 16G -smp cpus=16 \
	-object memory-backend-ram,size=4G,id=m0 \
	-object memory-backend-ram,size=4G,id=m1 \
	-object memory-backend-ram,size=4G,id=m2 \
	-object memory-backend-ram,size=4G,id=m3 \
	-numa node,memdev=m0,cpus=0-3,nodeid=0 \
	-numa node,memdev=m1,cpus=4-7,nodeid=1 \
	-numa node,memdev=m2,cpus=8-11,nodeid=2 \
	-numa node,memdev=m3,cpus=12-15,nodeid=3 \
	-numa dist,src=0,dst=1,val=15 \
    -numa dist,src=2,dst=3,val=15 \
    -numa dist,src=0,dst=2,val=20 \
    -numa dist,src=0,dst=3,val=20 \
    -numa dist,src=1,dst=2,val=20 \
    -numa dist,src=1,dst=3,val=20 \
	-boot menu=on -vnc :1 -uuid a53caec2-eb2d-4bca-819e-f2bbfb10e1fa \
	-netdev user,id=net0,net=10.0.2.15/24,hostfwd=tcp::5556-:22 \
	-device e1000,netdev=net0 \
	-netdev bridge,br=virbr1,id=net1,helper=/usr/libexec/qemu-bridge-helper \
	-device virtio-net-pci,netdev=net1,mac=EA:EB:D3:56:89:56 \
	-netdev bridge,br=virbr2,id=net2,helper=/usr/libexec/qemu-bridge-helper \
	-device virtio-net-pci,netdev=net2,mac=EA:EB:D3:57:89:57 \
	-cdrom /home/test/rh-linux-poc/ISO/CentOS-Stream-9-20240715.0-x86_64-dvd1.iso \
	-device nvme,drive=NVME1,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=7E1250DCD4B0A268 \
	-drive file=/home/test/rh-linux-poc/target-vm/disks/boot.qcow2,if=none,id=NVME1
exit
