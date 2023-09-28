#!/bin/bash
sudo reboot now
sudo apt install build-essential libncurses5-dev fakeroot xz-utils libelf-dev liblz4-tool unzip flex bison bc debhelper rsync libssl-dev:native 
mkdir ~/kernel
cd ~/kernel
wget https://github.com/nguyencanhtrung/kvm-pcie/blob/main/acso.patch
wget https://github.com/torvalds/linux/archive/refs/tags/v5.15.zip
unzip v5.15.zip
cd linux-5.15
sudo find /boot/ \( -iname "*config*" -a -iname "*`uname -r`*" \) -exec cp -i -t ./ {} \;
mv *`uname -r`* .config
ls /boot | grep config
patch -p1 < ../acso.patch
sudo make -j `getconf _NPROCESSORS_ONLN` bindeb-pkg LOCALVERSION=-acso KDEB_PKGVERSION=$(make kernelversion)-1