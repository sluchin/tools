#!/bin/sh

dir=`date "+%Y%m%d%H%M%S"`"-spec"
mkdir $dir

dmesg > "$dir/dmesg.log"
ifconfig -a > "$dir/ifconfig.log"
ethtool eth0 > "$dir/ethtool.log"
cat /proc/cpuinfo > "$dir/cpuinfo.log"
cat /proc/scsi/scsi > "$dir/scsi.log"
cat /proc/meminfo > "$dir/meminfo.log"
cat /proc/interrupts > "$dir/interrupts.log"
lscpu > "$dir/lscpu.log"
lspci > "$dir/lspci.log"
lsusb > "$dir/lsusb.log"
sysctl -a > "$dir/sysctl.log"
free > "$dir/free.log"
vmstat -s > "$dir/vmstat-s.log"
vmstat -n -d > "$dir/vmstat-d.log"
vmstat -f > "$dir/vmstat-f.log"

exit 0
