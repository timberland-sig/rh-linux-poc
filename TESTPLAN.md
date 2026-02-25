# NVMe/TCP Boot Test Plan

## 1st dimension tests:

First dimension test are run against a QEMU based linux soft target using
static IPv4, discovery NQNs, and no gateway.

1. installation
2. first boot
3. kdump
4. multipath, full reboot with NIC #1 down
5. multipath, full reboot with NIC #2 down (important!)
6. multipath NIC #1 down + up during OS runtime
7. multipath NIC #2 down + up during OS runtime

## 2nd dimension tests - networking

Second dimension tests repeat the first dimension tests with the following nbft configurations.

1. static IPv4, discovery NQNs, no gateway
2. static IPv4, subsystem NQNs, no gateway
3. static IPv6, discovery NQNs, no gateway
4. static IPv6, subsystem NQNs, no gateway
5. DHCP IPv4, discovery NQNs, no gateway
6. DHCP IPv4, subsystem NQNs, no gateway
7. DHCP IPv6, discovery NQNs, no gateway
8. DHCP IPv6, subsystem NQNs, no gateway
9. IPv4 and IPv6 with a gateway
10. tagged VLANs

## 3rd dimension tests - storage arrays / targets:

Third demension test repeat the above configurations and tests with the following hardware.

1. NetApp ONTAP
2. Dell PowerStore, no CDC
3. Dell PowerStore with CDC (Central Discovery Controller)
4. HPE Alletra
5. Pure Storage
6. Lightbits
7, Others

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

