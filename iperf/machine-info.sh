#!/bin/sh

dmesg > dmesg.log
ifconfig -a > ifconfig.log
ethtool eth0 > ethtool.log
cat /proc/cpuinfo > cpuinfo.log
cat /proc/meminfo > meminfo.log
lscpu > lscpu.log
lspci > lspci.log
lsusb > lsusb.log
sysctl -a > sysctl.log

exit 0
