# NVMe/TCP Boot Test Plan

## 1st dimension tests:

First dimension test are run against a QEMU based linux soft target using a
static IPv4 multipath (two host-vm networks with two target-vm controllers per
network) configuration with a Subsystem NQN and no gateway.

1. installation
2. cold boot
3. warm restart
4. kdump
5. multipath, full reboot with NIC #1 down
6. multipath, full reboot with NIC #2 down (important!)
7. multipath NIC #1 down + up during OS runtime
8. multipath NIC #2 down + up during OS runtime

The network config for 1st dimenstion testing is **static IPv4, Subsystem NQN, no gateway (two subnets)**

## 2nd dimension tests - networking

Second dimension tests repeat the first dimension tests with the following additional network configurations.

1. static IPv4, Subsystem NQN, with gateway
2. static IPv4, Subsystem NQN + NID, with gateway
3. DHCP IPv4 assigned host-vm address, Subsystem NQN, no gateway
4. DHCP IPv4 assigned host-vm address, Subsystem NQN + NID, no gateway
5. DHCP IPv4 assigned host-vm address, Subsystem NQN, with gateway
6. DHCP IPv4 assigned host-vm address, Subsystem NQN + NID, with gateway
7. DHCP IPv4 assigned host-vm and target-vm address, Subsystem NQN, no gateway
8. DHCP IPv4 assigned host-vm and target-vm address, Subsystem NQN + NID, no gateway
9. DHCP IPv4 assigned host-vm and target-vm address, Subsystem NQN, with gateway
10. DHCP IPv4 assigned host-vm and target-vm address, Subsystem NQN + NID , with gateway

## 3rd dimension tests - Discovery NQN

Third dimension tests repeat the 1st and 2nd dimension tests usind the Discovery NQN in the NBFT.

1. static IPv4, Discovery NQN, no gateway
2. static IPv4, Discovery NQN, with gateway
3. DHCP IPv4 assigned host-vm address, Discovery NQN, no gateway
4. DHCP IPv4 assigned host-vm address, Discovery NQN, with gateway
5. DHCP IPv4 assigned host-vm and target-vm address, Discovery NQN, no gateway
6. DHCP IPv4 assigned host-vm and target-vm address, Disovery NQN, with gateway

## 4th dimension tests - networking

Thirs dimension tests add the following network configurations to the above nbft configuraitons.

1. static IPv6, Subsystem NQN, no gateway
2. static IPv6, Discover NQN, no gateway
3. static IPv6, Subsystem NQN, with gateway
4. static IPv6, Discovery NQN, with gateway
5. DHCP IPv6 assigned host-vm address, Subsystem NQN, no gateway
6. DHCP IPv6 assigned host-vm address, Discovery NQN, no gateway
7. DHCP IPv6 assigned host-vm address, Subsystem NQN, with gateway
8. DHCP IPv6 assigned host-vm address, Discovery NQN, with gateway
9. DHCP IPv6 assigned host-vm and target-vm address, Subsystem NQN, no gateway
10. DHCP IPv6 assigned host-vm and target-vm address, Discovery NQN, no gateway
11. DHCP IPv6 assigned host-vm and target-vm address, Subsystem NQN, with gateway
12. DHCP IPv6 assigned host-vm and target-vm address, Discovery NQN, with gateway

## Target Storage array testing:

The Target Storage array tests repeat the above configurations and tests with the following hardware.

1. NetApp ONTAP
2. HPE Alletra
3. Pure Storage
4. Lightbits
5. Dell PowerStore, no CDC
6. Dell PowerStore with CDC (Central Discovery Controller)
7. Others

## Test Details

NVMe-TCP FIO Stress Test with NVMe-TCP BFS

### Basic Testing

1. Provision system to install onto the NVMe-TCP namespace and verify when the installation is complete:
2. Upon bootup, the nvme connections are already made:
3. Multipathing is enabled and working:
4. Generate I/O with FIO:

Expected Results

* FIO Completes
* No Data Errors
* No Kernel Stack Traces
* No Kernel Panics
* No Hangs
* Optimized Paths are available after test completes
* Non-Optimized Paths are available after test completes

### NVMe-TCP reset_controller during I/O with NVMe-TCP BFS

1. Repeat Basic Testing
2. Reset controllers with IO in progress
3. Verify Expected Results

### NVMe-TCP reset_controller stress with NVMe-TCP BFS

1. Repeat Basic Testing
2. Reset controllers repeatedly with IO in progress
3. Verify Expected Results


### NVMe-TCP rescan/reset_controller during I/O with NVMe-TCP BFS
1. Repeat Basic Testing
2. Rescan controllers with IO in progress
3. Verify Expected Results

### NVMe-TCP Offline CPU during I/O with NVMe-TCP BFS

1. Repeat Basic Testing
2. Offline/Online CPUs with IO in progress
3. Verify Expected Results


### NVMe-TCP connect/delete stress tests with NVMe-TCP BFS

1. Repeat Basic Testing
2. Add/Remove connections with IO in progress
3. Verify Expected Results

### NVMe-TCP Port Toggle with I/O with NVMe-TCP BFS

1. Repeat Basic Testing
2. Toggle swich ports off/on with IO in progress
3. Verify Expected Results

### NVMe-TCP Array Controller Failover during I/O with NVMe-TCP BFS

1. Repeat Basic Testing
2. Initiate controller failover/givebacke with IO in progress
3. Verify Expected Results

### NVMe-TCP Reboot Test with NVMe-TCP BFS

1. Repeat Basic Testing
2. Disable the switchport associated with NVMe-oF Subsystem
3. Reboot the host
2. Enable the switchport associated with NVMe-oF Subsystem
3. Verify Expected Results

Expected Results

* System successfully reboots
* System recovers all paths successfully after switchport is enabled following reboot
