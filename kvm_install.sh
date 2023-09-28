#!/bin/bash
RAM_SIZE=8192
VCPU=4
KVM_NAME=ukvm2004

#kvm installation
sudo apt update
sudo apt install qemu-kvm libvirt-clients libvirt-daemon-system virtinst bridge-utils cpu-checker virt-viewer virt-manager qemu-system
# add user to libvirt groups
cat /etc/group | grep libvirt | awk -F':' {'print $1'} | xargs -n1 sudo adduser $USER
# add user to kvm group also
sudo adduser $USER kvm
export LIBVIRT_DEFAULT_URI=qemu:///system
# create vm
wget https://releases.ubuntu.com/20.04.6/ubuntu-20.04.6-desktop-amd64.iso -O ~/kvm/mini.iso
virt-install --virt-type=kvm --name=$KVM_NAME --ram $RAM_SIZE --vcpus=$VCPU --virt-type=kvm --hvm --cdrom ~/kvm/mini.iso --network network=default --disk pool=default,size=20,bus=virtio,format=qcow2 --noautoconsole --machine q35
# view VM
virt-viewer ukvm2004