#!/usr/bin/env bash
# HERE should not contain spaces, or it will fail somewhere
HERE=$(cd $(dirname "$0") ; pwd)
# Wonderful library
source "$HERE"/libkoca.sh
# to get colored output
getColor _w white _e reset _p purple _r hired
do1="${_p}*${_e}"
do2="${_p}**${_e}"
do3="${_p}***${_e}"

# what module to run, by dafault
WHAT="packages interfaces rpi-update sources fstab fsck spi"
# File listing package to add and remove
PACKAGES_FILE=packages

ETCD_VERSION='0.5.0-alpha.4'
GO_VERSION='1.3.3'

# Third part to install : their dir and how to build/install them
declare -A src
src['/usr/src/aircrack-ng']="svn co http://svn.aircrack-ng.org/trunk/ /usr/src/aircrack-ng && cd /usr/src/aircrack-ng && apt-get install -y libnl-3-dev libnl-genl-3-dev && make install && apt-get -y purge libnl-3-dev libnl-genl-3-dev && airodump-ng-oui-update"
#src['/usr/src/wiringPi']="git clone git://git.drogon.net/wiringPi /usr/src/wiringPi && cd /usr/src/wiringPi && ./build"
#src['/usr/src/pcd8544']='git clone https://github.com/XavierBerger/pcd8544.git /usr/src/pcd8544 ; pip install wiringpi2 ; pip install spidev ; cd /usr/src/pcd8544 ; ./setup.py clean build ; ./setup.py install '
src['/usr/src/wiringPi']="git clone https://github.com/rm-hull/wiringPi /usr/src/wiringPi && cd /usr/src/wiringPi && ./build"
src['/usr/src/pcd8544']='git clone https://github.com/rm-hull/pcd8544.git /usr/src/pcd8544 && pip install pillow & cd /usr/src/pcd8544 && ./setup.py clean build && ./setup.py install '
src['/usr/src/wifite']="git clone https://github.com/Korsani/wifite.git /usr/src/wifite && mkdir -p $HOME/bin && ln -f -s /usr/src/wifite/wifite.py $HOME/bin/wifite.py"
src['/usr/src/dosfstools']="git clone http://daniel-baumann.ch/git/software/dosfstools.git /usr/src/dosfstools && cd /usr/src/dosfstools && make"
src["/usr/src/etcd-$ETCD_VERSION"]="curl -L http://koca-root.s3.amazonaws.com/go-$GO_VERSION-bin-armv6.tar.gz | tar -C $HERE -xzf - && curl -L https://github.com/coreos/etcd/archive/v$ETCD_VERSION.tar.gz | tar -C /usr/src -xzf - && cd /usr/src/etcd-$ETCD_VERSION && GOROOT=$HERE/go PATH=$PATH:$HERE/go/bin ./build && cp bin/etcd  /usr/local/sbin/ && cp bin/etcdctl bin/etcd-migrate /usr/local/bin/ && rm -rf $HERE/go "

totalMem=$(grep MemTotal /proc/meminfo  | awk '{print $2}')
# On exit, run this
trap '_post' 0

# Sanity check
[ $(id -u) -ne 0 ] && echo "I have to be run as root" && exit 1
[ $(uname -m) != "armv6l" ] && echo "Not on RPi" && exit 1

function _pre(){
	echo "$do3 executing _pre"
	mount / -o remount,async
}
function _post(){
	echo "$do3 executing _post"
	mount / -o remount,sync
}
function _check_default_route() {
	netstat -r | egrep -q 'default|*' && ping -c 1 -q www.free.fr >/dev/null 2>&1
}
function _warn(){
	[ -n "$WAS_WARNED" ] && return 0
	echo "${_r}!!!${_e} This ${_r}WILL${_e} break things. Please press enter to continue"
	read
	export WAS_WARNED=y
}
function help(){
	egrep "^function [^_]" $0 | sed -e 's/function \(.*\)().*/\1/' | xargs | tr ' ' '|'  | xargs echo -n "$0$_w"
	echo "$_e"
}
# (Un)install packages
# Package file is like that :
# +package_to_add
# -package_to_remove 
function packages() {
	_warn
	_check_default_route || return 1
	echo "$do1 Uninstalling packages"
	packages=$(egrep '^-' $PACKAGES_FILE | sed -e 's/^-//' | xargs)
	apt-get -q -y purge $packages
	echo "$do1 Updating existing packages"
	apt-get update ; apt-get upgrade -y
	echo "$do1 Installing packages"
	packages=$(egrep '^\+' $PACKAGES_FILE | sed -e 's/^\+//' | xargs)
	apt-get -y install $packages
	echo "$do1 Removing orphans"
	while [ -n "$(deborphan)" ]
	do
		apt-get -y purge $(deborphan)
	done
	echo "$do1 Running autoremove"
	apt-get -y autoremove 
	echo "$do1 Purging conf files of uninstalled packages"
	dpkg -l | egrep '^rc' | awk '{print $2}' | xargs apt-get -y purge
	curl www.korsani.fr/.screenrc -o /root/.screenrc
}
function interfaces() {
	_warn
	echo "$do1 Installing network interfaces"
	cp -a etc_network_interfaces /etc/network/interfaces 
}
# Third part software
function sources() {
	_check_default_route || return 1
	if [ -n "$1" ]
	then
		srcs="$*"
	else
		srcs="${!src[@]}"
	fi
	for d in $srcs
	do
		if [ ! -d $d ]
		then
			echo "$do1 Installing $(basename $d)"
			eval ${src[$d]}
		fi
	done
}
# Manipulate fstab : mount /tmp as tmpfs, and add sync options to / and /boot
# And umount /boot
function fstab() {
	_warn
	if [ ! -e "/etc/fstab.d/00-tmpfs.fstab" ]
	then
		echo "$do1 Installing tmp as tmpfs"
		echo "tmpfs           /tmp            tmpfs   defaults,size=$(expr $totalMem / 2)k        0       0" >> "/etc/fstab.d/00-tmpfs.fstab"
		mount -t tmpfs tmpfs /tmp
	fi
	echo "$do1 Puting sync option to /"
	sed -i.kocrack-root -e '/mmcblk0p2/c\/dev/mmcblk0p2  /               ext4    defaults,noatime,sync  0       1' /etc/fstab && mount -o remount /
	echo "$do1 Puting sync option to /boot"
	sed -i.kocrack-boot -e '/mmcblk0p1/c\/dev/mmcblk0p1  /boot           vfat    defaults,noauto,sync          0       2' /etc/fstab
	umount /boot 2>/dev/null
}
# fsck /boot
# Need external dosfstools as the one shipped can't remove dirty flag (sic)
function fsck(){
	_warn
	if  $(dmesg | grep -q 'FAT-fs (mmcblk0p1): Volume was not properly unmounted') 
	then
		sources /usr/src/dosfstools
		echo "$do1 fsck /boot"
		cd /usr/src/dosfstools
		umount /boot >/dev/null
		./fsck.fat -a -V /dev/mmcblk0p1
	fi
}
# Update rpi
function rpi-update(){
	mount /boot
	/usr/bin/rpi-update
	umount /boot
}
# Load spi module at boot
function spi() {
	echo "$do1 Unblacklisting spi-bcm2708"
	grep -v 'spi-bcm2708' /etc/modprobe.d/raspi-blacklist.conf > /tmp/$$
	mv /tmp/$$ /etc/modprobe.d/raspi-blacklist.conf
}
#####
# Run all of this
#####

# You can call me $0 part_to_run
if [ -n "$*" ]
then
	WHAT="$*"
fi
echo "$do3 Will run : ${_w}$WHAT${_e}"
_pre
for what in $WHAT
do
	echo "$do2 Proceeding with ${_w}$what${_e}"
	$what
done
