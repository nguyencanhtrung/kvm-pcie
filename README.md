# KVM with PCIe Passthrough

This guide will walk you through the process of installing KVM (Kernel-based Virtual Machine) and setting up PCIe passthrough on a Linux system.

## Prerequisites

Before getting started, ensure that you meet the following prerequisites:

1. **Linux System**: Ubuntu 20.04 - kernel v5.15.

2. **Bios**: Make sure Intel Virtualization Technology (Intel VT) and Intel ® VT-d must be enabled from server BIOS

3. **CPU Support**: Check if your CPU supports virtualization and IOMMU (Input-Output Memory Management Unit) by running:

    ```
    egrep -c '(vmx|svm)' /proc/cpuinfo
    ```
    If the command returns a value of 0, your processor is not capable of running KVM. On the other hand, any other number means you can proceed with the installation.

    You are now ready to start installing KVM.

## Step 1: Install KVM

### On Ubuntu:

1. First, install KVM and assorted tools

    ```shell
    sudo apt update
    sudo apt install qemu-kvm libvirt-clients libvirt-daemon-system virtinst bridge-utils cpu-checker virt-viewer
    ```

2. Now, check if your system can use KVM acceleration by typing:

    ```shell
    sudo kvm-ok
    ```

The output should look like this:

```shell
tesla@tesla:~/kvm$ kvm-ok
INFO: /dev/kvm exists
KVM acceleration can be used
```

Then run the virt-host-validate utility to run a whole set of checks against your virtualization ability and KVM readiness.

```shell
$ sudo virt-host-validate
QEMU: Checking for hardware virtualization                                 : PASS
QEMU: Checking if device /dev/kvm exists                                   : PASS
QEMU: Checking if device /dev/kvm is accessible                            : PASS
QEMU: Checking if device /dev/vhost-net exists                             : PASS
QEMU: Checking if device /dev/net/tun exists                               : PASS
QEMU: Checking for cgroup 'memory' controller support                      : PASS
QEMU: Checking for cgroup 'memory' controller mount-point                  : PASS
QEMU: Checking for cgroup 'cpu' controller support                         : PASS
QEMU: Checking for cgroup 'cpu' controller mount-point                     : PASS
QEMU: Checking for cgroup 'cpuacct' controller support                     : PASS
QEMU: Checking for cgroup 'cpuacct' controller mount-point                 : PASS
QEMU: Checking for cgroup 'cpuset' controller support                      : PASS
QEMU: Checking for cgroup 'cpuset' controller mount-point                  : PASS
QEMU: Checking for cgroup 'devices' controller support                     : PASS
QEMU: Checking for cgroup 'devices' controller mount-point                 : PASS
QEMU: Checking for cgroup 'blkio' controller support                       : PASS
QEMU: Checking for cgroup 'blkio' controller mount-point                   : PASS
QEMU: Checking for device assignment IOMMU support                         : PASS
 LXC: Checking for Linux >= 2.6.26                                         : PASS
 LXC: Checking for namespace ipc                                           : PASS
 LXC: Checking for namespace mnt                                           : PASS
 LXC: Checking for namespace pid                                           : PASS
 LXC: Checking for namespace uts                                           : PASS
 LXC: Checking for namespace net                                           : PASS
 LXC: Checking for namespace user                                          : PASS
 LXC: Checking for cgroup 'memory' controller support                      : PASS
 LXC: Checking for cgroup 'memory' controller mount-point                  : PASS
 LXC: Checking for cgroup 'cpu' controller support                         : PASS
 LXC: Checking for cgroup 'cpu' controller mount-point                     : PASS
 LXC: Checking for cgroup 'cpuacct' controller support                     : PASS
 LXC: Checking for cgroup 'cpuacct' controller mount-point                 : PASS
 LXC: Checking for cgroup 'cpuset' controller support                      : PASS
 LXC: Checking for cgroup 'cpuset' controller mount-point                  : PASS
 LXC: Checking for cgroup 'devices' controller support                     : PASS
 LXC: Checking for cgroup 'devices' controller mount-point                 : PASS
 LXC: Checking for cgroup 'blkio' controller support                       : PASS
 LXC: Checking for cgroup 'blkio' controller mount-point                   : PASS
 LXC: Checking if device /sys/fs/fuse/connections exists                   : PASS
```

3. Add user to libvirt groups

To allow the current user to manage the guest VM without sudo, we can add ourselves to all of the libvirt groups (e.g. libvirt, libvirt-qemu) and the kvm group

```shell
cat /etc/group | grep libvirt | awk -F':' {'print $1'} | xargs -n1 sudo adduser $USER

# add user to kvm group also
sudo adduser $USER kvm

# relogin, then show group membership
exec su -l $USER
id | grep libvirt
```

Group membership requires a user to log back in, so if the `id` command does not show your libvirt* group membership, logout and log back in, or try `exec su -l $USER`.


## Step 2: Configure IOMMU

1. Open the grub configuration file:

    ```shell
    sudo nano /etc/default/grub
    ```

2. Add the `amd_iommu=on` or `intel_iommu=on` flags to the `GRUB_CMDLINE_LINUX` variable:

    ```shell
    GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on pcie_acs_override=downstream,multifunction vfio-pci.ids=10ee:5000,10ee:5001"
    ```

    We can identify the pci.ids using the below command.


    ```
    $ lspci -nn | grep "Xilinx"

    01:00.0 Processing accelerators [1200]: Xilinx Corporation Device [10ee:5000]
    01:00.1 Processing accelerators [1200]: Xilinx Corporation Device [10ee:5001]

    ```



3. Update grub:

    ```shell
    sudo update-grub
    ```

    or

    ```shell
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    ```


4. Reboot your machine:

    ```shell
    sudo reboot
    ```

## Step 3: 

1. Create a new file under `/etc/modprobe.d/vfio.conf` add the below

    ```shell
    options vfio-pci ids=10ee:5000,10ee:5001
    ```

2. Update the `initramfs` using the below command and reboot the host.

    ```shell
    sudo update-initramfs -u
    ```


## Step 4: Configure PCIe Passthrough

1. Find information about the PCIe card you want to passthrough:

    ```shell
    lspci | grep VGA
    ```

Note down the ID of the card, e.g., `01:00.0`.

2. Create a virtual machine XML configuration file with libvirt. Edit the virtual machine XML file as provided in this repository.

3. Adjust the virtual machine configuration to use the selected PCIe card.

## Step 5: Run the Virtual Machine

Once you've configured everything, start the virtual machine with the following command:

    ```shell
    virt-install --name myvm --ram 4096 --vcpus 2 --disk path=/path/to/disk.img,size=20 --graphics none --os-type linux --os-variant ubuntu20.04 --console pty,target_type=serial --extra-args 'console=ttyS0'
    ```

Replace `myvm` with your virtual machine's name and adjust other options as needed.

## Step 5: Access the Virtual Machine

You can access the virtual machine via SSH or connect to it via remote graphical interface using VNC (if configured).

## Step 6: Complete Installation

Once the virtual machine is running, you can complete the operating system installation and install the software you want to use.




Reference:

Splitting IOMMU groups
https://www.youtube.com/watch?v=qQiMMeVNw-o