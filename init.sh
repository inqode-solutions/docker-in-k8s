#!/bin/bash
set -xue -o pipefail

mount -t proc proc /proc/
mount -t sysfs sys /sys/

# Initialize cgroup2 mount
mount -t cgroup2 none /sys/fs/cgroup
# Evacuate the current process to "init.tmp" group so that we can configure subtree_control
mkdir /sys/fs/cgroup/init.tmp
echo $$ >/sys/fs/cgroup/init.tmp/cgroup.procs
cat /sys/fs/cgroup/cgroup.controllers
echo '+cpu +io +memory +pids' >/sys/fs/cgroup/cgroup.subtree_control
# Restore the "init.tmp" group to the top-level group
echo $$ >/sys/fs/cgroup/cgroup.procs
rmdir /sys/fs/cgroup/init.tmp

mount -t tmpfs none /run
mkdir /dev/pts
mount -t devpts devpts /dev/pts
rm /dev/ptmx
ln -s /dev/pts/ptmx /dev/ptmx

rngd -r /dev/urandom

mount -t ext4 /persistent/var_lib_docker.img /var/lib/docker/

ip link set dev lo up
ip link set dev vec0 up
ip addr add 10.0.2.100/24 dev vec0
ip route add default via 10.0.2.2

#connect to the parent docker container for reverse forwarding of the docker socket
ssh -f -N -o StrictHostKeyChecking=no \
    -R0.0.0.0:2375:127.0.0.1:2375 \
    -R0.0.0.0:2376:127.0.0.1:2376 \
    -p 2222 \
    -i /home/user/.ssh/id_rsa \
    user@10.0.2.2

PATH=/usr/bin:$PATH dockerd --userland-proxy-path=$(which diuid-docker-proxy) -H tcp://127.0.0.1:2375

ret=$?
if [ $ret -ne 0 ]; then
	exit 1
fi
/sbin/halt -f
