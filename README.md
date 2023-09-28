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

1. First, install KVM and assorted tools

    ```shell
    sudo apt update
    sudo apt install qemu-kvm libvirt-clients libvirt-daemon-system virtinst bridge-utils cpu-checker virt-viewer virt-manager qemu-system
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

4. QEMU connection to system

If not explicitly set, the userspace QEMU connection will be to `qemu:///session`, and not to `qemu:///system`.  This will cause you to see different domains, networks, and disk pool when executing virsh as your regular user versus sudo.

Modify your profile so that the environment variable below is exported to your login sessions.

```shell
# use same connection and objects as sudo
export LIBVIRT_DEFAULT_URI=qemu:///system
```

5. Default network

By default, KVM creates a virtual switch that shows up as a host interface named `virbr0` using 192.168.122.0/24.

This interface should be visible from the Host using the “ip” command below.

```shell
$ ip addr show virbr0
3: virbr0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
    link/ether 00:00:00:00:00:00 brd ff:ff:ff:ff:ff:ff
    inet 192.168.122.1/24 brd 192.168.122.255 scope global virbr0
       valid_lft forever preferred_lft forever
```

`virbr0` operates in NAT mode, which allows the guest OS to communicate out, but only allowing the Host(and those VMs in its subnet) to make incoming connections.

6. Bridge network

To enable guest VMs on the same network as the Host, you should create a bridged network to your physical interface (e.g. eth0, ens4, epn1s0).

Read my article here for how to use NetPlan on Ubuntu to bridge your physical network interface to `br0` at the OS level.  And then use that to create a libvirt network named `host-bridge` that uses `br0`.

```shell
# bridge to physical network
$ virsh net-dumpxml host-bridge

<network connections='2'>
  <name>host-bridge</name>
  <uuid>44d2c3f5-6301-4fc6-be81-5ae2be4a47d8</uuid>
  <forward mode='bridge'/>
  <bridge name='br0'/>
</network>
```

This `host-bridge` will be required in later articles.

Instruction to setup host's OS to create `br0` [here](https://fabianlee.org/2019/04/01/kvm-creating-a-bridged-network-with-netplan-on-ubuntu-bionic/)

7. Enable IPv4 forwarding on KVM host

In order to handle NAT and routed networks for KVM, enable IPv4 forwarding on this host.

```shell
# this needs to be "1"
cat /proc/sys/net/ipv4/ip_forward
# if not, then add it
echo net.ipv4.ip_forward=1 | sudo tee -a /etc/sysctl.conf

# make permanent
sudo sysctl -p /etc/sysctl.conf
```

8. Default storage pool

The “default” storage pool for guest disks is `/var/lib/libvirt/images`.   This is fine for test purposes, but if you have another mount that you want to use for guest OS disks, then you should create a custom storage pool.

Below are the commands to create a “kvmpool” on an SSD mounted at `/data/kvm/pool`.

```shell
$ virsh pool-list --all
 Name                 State      Autostart 
-------------------------------------------
 default              active     yes       

$ virsh pool-define-as kvmpool --type dir --target /data/kvm/pool
Pool kvmpool defined
$ virsh pool-list --all
$ virsh pool-start kvmpool
$ virsh pool-autostart kvmpool

$ virsh pool-list --all
 Name                 State      Autostart 
-------------------------------------------
 default              active     yes       
 kvmpool              active     yes
```

9. Create basic VM using `virt-install`

In order to test you need an OS boot image.  Since we are on an Ubuntu host, let’s download the ISO for the network installer of Ubuntu 20.04 Focal.  This file is only 74Mb, so it is perfect for testing.  When complete, you should have a local file named `~/kvm/mini.iso`


```shell
wget https://releases.ubuntu.com/20.04.6/ubuntu-20.04.6-desktop-amd64.iso -O ~/kvm/mini.iso
```

First list what virtual machines are running on our host:

```shell
# chown is only necessary if virsh was run previously as sudo
ls -l ~/.virtinst
sudo chown -R $USER:$USER ~/.virtinst

# list VMs
virsh list --all
```

This should return an empty list of VMs, because no guest OS have been deployed. Create your first guest VM with 4 vcpu/8G RAM using the default virbr0 NAT network and default pool storage.


```shell
virt-install --virt-type=kvm --name=ukvm2004 --ram 8192 --vcpus=4 --virt-type=kvm --hvm --cdrom ~/kvm/mini.iso --network network=default --disk pool=default,size=20,bus=virtio,format=qcow2 --noautoconsole --machine q35
```

Note: When creating VM's using virt-manager, make sure to also select `q35` as the machine type for full support of pcie in your guests.

Open the VM

```shell
# open console to VM
virt-viewer ukvm2004
```

`virt-viewer` will popup a window for the Guest OS, when you click the mouse in the window and then press <ENTER> you will see the initial Ubuntu network install screen.

If you want to delete this guest OS completely, close the GUI window opened with virt-viewer, then use the following commands:

```shell
virsh destroy ukvm2004
virsh undefine ukvm2004
```

`virt-manager` provides a convenient interface for creating or managing a guest OS, and any guest OS you create from the CLI using virt-install will show up in this list also.


**Reference:** Visit [kvm all commands](https://fabianlee.org/2018/08/27/kvm-bare-metal-virtualization-on-ubuntu-with-kvm/)  and [Xilinx instruction](https://www.xilinx.com/developer/articles/using-alveo-data-center-accelerator-cards-in-a-kvm-environment.html)


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


## Step: Patched ACS kernel

```shell
sudo apt install build-essential libncurses5-dev fakeroot xz-utils libelf-dev liblz4-tool unzip flex bison bc debhelper rsync libssl-dev:native
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