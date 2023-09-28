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

### 1. First, install KVM and assorted tools

```shell
sudo apt update
sudo apt install qemu-kvm libvirt-clients libvirt-daemon-system virtinst bridge-utils cpu-checker virt-viewer virt-manager qemu-system
    ```

### 2. Now, check if your system can use KVM acceleration by typing:

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

### 3. Add user to libvirt groups

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

### 4. QEMU connection to system

If not explicitly set, the userspace QEMU connection will be to `qemu:///session`, and not to `qemu:///system`.  This will cause you to see different domains, networks, and disk pool when executing virsh as your regular user versus sudo.

Modify your profile so that the environment variable below is exported to your login sessions.

```shell
# use same connection and objects as sudo
export LIBVIRT_DEFAULT_URI=qemu:///system
```

### 5. Default network

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

### 6. Bridge network

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

### 7. Enable IPv4 forwarding on KVM host

In order to handle NAT and routed networks for KVM, enable IPv4 forwarding on this host.

```shell
# this needs to be "1"
cat /proc/sys/net/ipv4/ip_forward
# if not, then add it
echo net.ipv4.ip_forward=1 | sudo tee -a /etc/sysctl.conf

# make permanent
sudo sysctl -p /etc/sysctl.conf
```

### 8. Default storage pool

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

## Step 2: Create `ukvm2004` VM using `virt-install`

### 1. Download ubuntu 20.04 focal iso

In order to test you need an OS boot image.  Since we are on an Ubuntu host, let’s download the ISO for the network installer of Ubuntu 20.04 Focal. When complete, you should have a local file named `~/kvm/mini.iso`


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

This should return an empty list of VMs, because no guest OS have been deployed. 

### 2. Installing `ukvm2004` VM

```shell
virt-install --virt-type=kvm --name=ukvm2004 --ram 8192 --vcpus=4 --virt-type=kvm --hvm --cdrom ~/kvm/mini.iso --network network=default --disk pool=default,size=20,bus=virtio,format=qcow2 --noautoconsole --machine q35
```

Note: When creating VM's using virt-manager, make sure to also select `q35` as the machine type for full support of pcie in your guests.

* VM name:   `ukvm2004`
* VCPU: `4`
* RAM:  `8G`
* Network: `default virbr0 NAT network`
* Pool storage:  `default` and size = 20GB
* Graphic: `default` - spice

### 3. Open the VM

```shell
# open console to VM
virt-viewer ukvm2004
```

`virt-viewer` will popup a window for the Guest OS, when you click the mouse in the window and then press <ENTER> you will see the initial Ubuntu network install screen.

`virt-manager` provides a convenient interface for creating or managing a guest OS, and any guest OS you create from the CLI using virt-install will show up in this list also.


### 4. Stop and delete VM

If you want to delete this guest OS completely, close the GUI window opened with virt-viewer, then use the following commands:

```shell
virsh destroy ukvm2004
virsh undefine ukvm2004
```

**Reference:** Visit [kvm all commands](https://fabianlee.org/2018/08/27/kvm-bare-metal-virtualization-on-ubuntu-with-kvm/)  and [Xilinx instruction](https://www.xilinx.com/developer/articles/using-alveo-data-center-accelerator-cards-in-a-kvm-environment.html)


## Step 3: Configure IOMMU and passthrough with `vfio-pci` driver for Xilinx AU200 card

1. Open the grub configuration file:

```shell
sudo nano /etc/default/grub
```

2. Add the `amd_iommu=on` or `intel_iommu=on` flags to the `GRUB_CMDLINE_LINUX` variable:

```shell
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on pcie_acs_override=downstream,multifunction vfio-pci.ids=10ee:5000,10ee:5001"
```

We can identify the pci.ids using the below command.


```shell
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

Check the new content of Grub by

```shell
cat /proc/cmdline

BOOT_IMAGE=/boot/vmlinuz-5.15.0-acso root=UUID=2006ace4-1a9a-4d7f-aa7c-685cae3abe4c ro quiet intel_iommu=on pcie_acs_override=downstream,multifunction vfio-pci.ids=10ee:5000,10ee:5001
```


4. Create a new file under `/etc/modprobe.d/vfio.conf` add the below

    ```shell
    options vfio-pci ids=10ee:5000,10ee:5001
    ```

5. Update the `initramfs` using the below command and reboot the host.

    ```shell
    sudo update-initramfs -u
    ```

After the reboot of the host, check NVIDA is configure for Pass-through using the below command.

```
$ lspci -k
```

`Kernel driver in use: vfio-pci` is OK

```
01:00.0 Processing accelerators: Xilinx Corporation Device 5000
    Subsystem: Xilinx Corporation Device 000e
    Kernel driver in use: vfio-pci
    Kernel modules: xclmgmt
01:00.1 Processing accelerators: Xilinx Corporation Device 5001
    Subsystem: Xilinx Corporation Device 000e
    Kernel driver in use: vfio-pci
    Kernel modules: xocl

```

**Reference:** Visit [URL](https://medium0.com/techbeatly/virtual-machine-with-gpu-enabled-on-ubuntu-using-kvm-on-ubuntu-22-4-f0354ba74b1)


## Step 4: Check IOMMU group with provided script in this repo

```shell
sudo chmod +x iommu_viewer.sh
./iommu_viewer.sh
```


```
...
Group:  1   0000:00:01.0 PCI bridge [0604]: Intel Corporation Xeon E3-1200 v5/E3-1500 v5/6th Gen Core Processor PCIe Controller (x16) [8086:1901] (rev 0a)   Driver: pcieport
Group:  1   0000:00:01.1 PCI bridge [0604]: Intel Corporation Xeon E3-1200 v5/E3-1500 v5/6th Gen Core Processor PCIe Controller (x8) [8086:1905] (rev 0a)   Driver: pcieport
Group:  1   0000:01:00.0 Processing accelerators [1200]: Xilinx Corporation Device [10ee:5000]   Driver: vfio-pci
Group:  1   0000:01:00.1 Processing accelerators [1200]: Xilinx Corporation Device [10ee:5001]   Driver: vfio-pci
Group:  1   0000:02:00.0 VGA compatible controller [0300]: NVIDIA Corporation Device [10de:2489] (rev a1)   Driver: nvidia
Group:  1   0000:02:00.1 Audio device [0403]: NVIDIA Corporation Device [10de:228b] (rev a1)   Driver: snd_hda_intel
Group:  2   0000:00:02.0 Display controller [0380]: Intel Corporation UHD Graphics 630 (Desktop 9 Series) [8086:3e98]   Driver: i915
Group:  3   0000:00:12.0 Signal processing controller [1180]: Intel Corporation Cannon Lake PCH Thermal Controller [8086:a379] (rev 10)   Driver: intel_pch_thermal
Group:  4   0000:00:14.0 USB controller [0c03]: Intel Corporation Cannon Lake PCH USB 3.1 xHCI Host Controller [8086:a36d] (rev 10)   Driver: xhci_hcd
...
```

Now, you can see the Xilinx card is in the same IOMMU group `Group 1` with NVIDIA GPU. Passing through Xilinx card to KVM requires all devices in the same group use the same `vfio-pci`

Watch [this](https://www.youtube.com/watch?v=qQiMMeVNw-o) to understand more. Splitting IOMMU is required in this case, however my machine which includes a MOBO (Z390 Gigabyte Wifi Pro + CPU 9900K) does not support `pcie_acs_override`. Therefore, even putting the grub command like above, the IOMMU is not splitting as expectation. To make it works, we have to create a Patched ACS kernel and running this kernel instead. Step 5 shows step to do so.

## Step 5: Patched ACS kernel

### 1. Download ACS patch and original kernel to build

On the host machine, 

```shell
sudo apt update && sudo apt upgrade
sudo reboot now
sudo apt install build-essential libncurses5-dev fakeroot xz-utils libelf-dev liblz4-tool unzip flex bison bc debhelper rsync libssl-dev:native 
mkdir ~/kernel
cd ~/kernel
wget https://github.com/nguyencanhtrung/kvm-pcie/blob/main/acso.patch
wget https://github.com/torvalds/linux/archive/refs/tags/v5.15.zip
unzip v5.15.zip
```

### 2. Editing config file to avoid building error


```shell
cd linux-5.15
sudo find /boot/ \( -iname "*config*" -a -iname "*`uname -r`*" \) -exec cp -i -t ./ {} \;
mv *`uname -r`* .config
ls /boot | grep config
sudo nano .config
```

Use `Ctrl+w` to search for `CONFIG_SYSTEM_TRUSTED_KEYS` on nano and comment out the line like:
`#CONFIG_SYSTEM_TRUSTED_KEYS`
`Ctrl+x` to Save & Exit


### 3. Apply patches ACS

```shell
patch -p1 < ../acso.patch
```

Output should be something like this:


```shell
patching file Documentation/admin-guide/kernel-parameters.txt
Hunk #1 succeeded at 3892 (offset 383 lines).
patching file drivers/pci/quirks.c
Hunk #1 succeeded at 3515 with fuzz 2 (offset -29 lines).
Hunk #2 succeeded at 5049 with fuzz 1 (offset 153 lines).
```

This shows a successful patch that required a fuzz (slight offset change) because the patch was made for an earlier kernel version. As long as there isn't an error this should be okay.
Run the following command to build the kernel:

### 4. Build patched kernel

```shell
sudo make -j `getconf _NPROCESSORS_ONLN` bindeb-pkg LOCALVERSION=-acso KDEB_PKGVERSION=$(make kernelversion)-1
```

Press Enter for all prompts.

**Note:** If you get a build failure remove the "-j `getconf _NPROCESSORS_ONLN`"" part from the make line and run it again to see the error with more detail and fix it.


### 5. Install the patched kernel

When you get a successful build run the following to install the kernel:

```shell
ls ../linux-*.deb
sudo dpkg -i ../linux-*.deb
```

```shell
sudo -i
echo "vfio" >> /etc/modules
echo "vfio_iommu_type1" >> /etc/modules
echo "vfio_pci" >> /etc/modules
echo "kvm" >> /etc/modules
echo "kvm_intel" >> /etc/modules
```

```shell
update-initramfs -u
reboot
```

When the system rebooting, hold `SHIFT` to entering the patched kernel  `Advanced Ubuntu` > `5.15.0-acso`

### 6. In case booting hang (optional)

Reboot the system hold `SHIFT` to entering the patched kernel  `Advanced Ubuntu` > `5.15.0-acso`

Press `e` to edit the grub

Appending `nomodeset` in the command line (watch video in the following reference to know the detail)

```
linux     /boot/vmlinuz ....    .... downstream nomodeset ...
```

Then press `F10` to save and reload.


After rebooting, let's check IOMMU group now

```shell
tesla@tesla:~/kvm$ ./iommu_viewer.sh 
Please be patient. This may take a couple seconds.
Group:  0   0000:00:00.0 Host bridge [0600]: Intel Corporation 8th Gen Core 8-core Desktop Processor Host Bridge/DRAM Registers [Coffee Lake S] [8086:3e30] (rev 0a)   Driver: skl_uncore
Group:  1   0000:00:01.0 PCI bridge [0604]: Intel Corporation Xeon E3-1200 v5/E3-1500 v5/6th Gen Core Processor PCIe Controller (x16) [8086:1901] (rev 0a)   Driver: pcieport
Group:  2   0000:00:01.1 PCI bridge [0604]: Intel Corporation Xeon E3-1200 v5/E3-1500 v5/6th Gen Core Processor PCIe Controller (x8) [8086:1905] (rev 0a)   Driver: pcieport
Group:  3   0000:00:12.0 Signal processing controller [1180]: Intel Corporation Cannon Lake PCH Thermal Controller [8086:a379] (rev 10)   Driver: intel_pch_thermal
Group:  4   0000:00:14.0 USB controller [0c03]: Intel Corporation Cannon Lake PCH USB 3.1 xHCI Host Controller [8086:a36d] (rev 10)   Driver: xhci_hcd
Group:  4   0000:00:14.2 RAM memory [0500]: Intel Corporation Cannon Lake PCH Shared SRAM [8086:a36f] (rev 10)
Group:  5   0000:00:14.3 Network controller [0280]: Intel Corporation Wireless-AC 9560 [Jefferson Peak] [8086:a370] (rev 10)   Driver: iwlwifi
Group:  6   0000:00:16.0 Communication controller [0780]: Intel Corporation Cannon Lake PCH HECI Controller [8086:a360] (rev 10)   Driver: mei_me
Group:  7   0000:00:17.0 SATA controller [0106]: Intel Corporation Cannon Lake PCH SATA AHCI Controller [8086:a352] (rev 10)   Driver: ahci
Group:  8   0000:00:1b.0 PCI bridge [0604]: Intel Corporation Cannon Lake PCH PCI Express Root Port #17 [8086:a340] (rev f0)   Driver: pcieport
Group:  9   0000:00:1c.0 PCI bridge [0604]: Intel Corporation Cannon Lake PCH PCI Express Root Port #1 [8086:a338] (rev f0)   Driver: pcieport
Group:  10  0000:00:1d.0 PCI bridge [0604]: Intel Corporation Cannon Lake PCH PCI Express Root Port #9 [8086:a330] (rev f0)   Driver: pcieport
Group:  11  0000:00:1f.0 ISA bridge [0601]: Intel Corporation Z390 Chipset LPC/eSPI Controller [8086:a305] (rev 10)
Group:  11  0000:00:1f.3 Audio device [0403]: Intel Corporation Cannon Lake PCH cAVS [8086:a348] (rev 10)   Driver: snd_hda_intel
Group:  11  0000:00:1f.4 SMBus [0c05]: Intel Corporation Cannon Lake PCH SMBus Controller [8086:a323] (rev 10)   Driver: i801_smbus
Group:  11  0000:00:1f.5 Serial bus controller [0c80]: Intel Corporation Cannon Lake PCH SPI Controller [8086:a324] (rev 10)
Group:  11  0000:00:1f.6 Ethernet controller [0200]: Intel Corporation Ethernet Connection (7) I219-V [8086:15bc] (rev 10)   Driver: e1000e
Group:  12  0000:01:00.0 Processing accelerators [1200]: Xilinx Corporation Device [10ee:5000]   Driver: vfio-pci
Group:  13  0000:01:00.1 Processing accelerators [1200]: Xilinx Corporation Device [10ee:5001]   Driver: vfio-pci
Group:  14  0000:02:00.0 VGA compatible controller [0300]: NVIDIA Corporation Device [10de:2489] (rev a1)   Driver: nvidia
Group:  15  0000:02:00.1 Audio device [0403]: NVIDIA Corporation Device [10de:228b] (rev a1)   Driver: snd_hda_intel
Group:  16  0000:03:00.0 Non-Volatile memory controller [0108]: Samsung Electronics Co Ltd NVMe SSD Controller SM981/PM981/PM983 [144d:a808]   Driver: nvme
Group:  17  0000:05:00.0 Non-Volatile memory controller [0108]: Samsung Electronics Co Ltd NVMe SSD Controller SM981/PM981/PM983 [144d:a808]   Driver: nvme
```

Now, Xilinx card and Nvidia card are in different IOMMU groups

### 7. Change Grub to auto boot to patched kernel

```shell
sudo nano /etc/default/grub
```

Change

```shell
GRUB_DEFAULT="1>4"

```

Then,

```
sudo update-grub
reboot
```

**Note:** The index `1` or `4` is counted based on the order in the menu (after rebooting, hold `SHIFT`).

```
Ubuntu              (index = 0)
Advanced Ubuntu     (index = 1)
    ubuntu-kernel-xxx           (index = 0)
    ubuntu-kernel-xxx-recovery  (index = 1)
    ubuntu-kernel-xxx           (index = 2)
    ubuntu-kernel-xxx-recovery  (index = 3)
    ubuntu-kernel-xxx           (index = 4)
...
```


**Reference:** Visit [video](https://www.youtube.com/watch?v=JBEzshbGPhQ)

[Patched ACS](https://queuecumber.gitlab.io/linux-acs-override/)

[Original script - scroll to the end of page](https://gitlab.com/Queuecumber/linux-acs-override/-/issues/12)

[Repo](https://github.com/benbaker76/linux-acs-override)


## Step 6: Configure PCIe Passthrough for VM

1. Find information about the PCIe card you want to passthrough:

    ```shell
    lspci | grep VGA
    ```

Note down the ID of the card, e.g., `01:00.0`.

2. Create a virtual machine XML configuration file with libvirt. Edit the virtual machine XML file as provided in this repository.

3. Adjust the virtual machine configuration to use the selected PCIe card.

## Step 7: Run the Virtual Machine

Once you've configured everything, start the virtual machine with the following command:

    ```shell
    virt-install --name myvm --ram 4096 --vcpus 2 --disk path=/path/to/disk.img,size=20 --graphics none --os-type linux --os-variant ubuntu20.04 --console pty,target_type=serial --extra-args 'console=ttyS0'
    ```

Replace `myvm` with your virtual machine's name and adjust other options as needed.

## Step 8: Access the Virtual Machine

You can access the virtual machine via SSH or connect to it via remote graphical interface using VNC (if configured).

## Step 9: Complete Installation

Once the virtual machine is running, you can complete the operating system installation and install the software you want to use.
