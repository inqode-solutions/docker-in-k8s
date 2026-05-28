#!/bin/bash

#set -xue -o pipefail
ARGS=$@

echo "Docker: $(dockerd --version)"
echo "Kernel: $(/linux/linux --version)"
echo "Rootfs: $(lsb_release -ds)"
echo
echo "Configuration: MEM=$MEM DISK=$DISK"

# Create the ext4 volume image for /var/lib/docker
if [ ! -f /persistent/var_lib_docker.img ]; then
    echo "Formatting /persistent/var_lib_docker.img"
    dd if=/dev/zero of=/persistent/var_lib_docker.img bs=1 count=0 seek=${DISK} > /dev/null 2>&1
    mkfs.ext4 /persistent/var_lib_docker.img > /dev/null 2>&1
fi

# verify TMPDIR configuration
if [ $(stat --file-system --format=%T $TMPDIR) != tmpfs ]; then
    echo "For better performance, consider mounting a tmpfs on $TMPDIR like this: \`docker run --tmpfs $TMPDIR:rw,nosuid,nodev,exec,size=8g\`"
fi

/sbin/start-stop-daemon --start --background --make-pidfile --pidfile /tmp/sshd.pid --exec /bin/bash -- -c "exec /usr/sbin/sshd -D -p 2222 -h /etc/ssh/ssh_host_rsa_key -o "UsePrivilegeSeparation no" -o "UsePAM no" -o "GatewayPorts yes" > /tmp/slirp4netns-bess.log 2>&1"
/sbin/start-stop-daemon --start --background --make-pidfile --pidfile /tmp/slirp4netns.pid --exec /bin/bash -- -c "exec slirp4netns --target-type=bess /run/slirp4netns-bess.sock > /tmp/slirp4netns-bess.log 2>&1"
/sbin/start-stop-daemon --start --background --make-pidfile --pidfile /tmp/kernel.pid --exec /bin/bash -- -c "exec /linux/linux rootfstype=hostfs rw vec0:transport=bess,dst=/run/slirp4netns-bess.sock,depth=128,gro=1 mem=$MEM init=/init.sh > /tmp/kernel.log 2>&1"

export DOCKER_HOST=tcp://127.0.0.1:2375

echo -n "waiting for dockerd "
while true; do
	if docker version 2>/dev/null >/dev/null; then
		echo ""
		break
	fi
	if ! /sbin/start-stop-daemon --status --pidfile /tmp/kernel.pid; then
		echo ""
		echo failed to start uml kernel:
		cat /tmp/kernel.log
		exit 1
	fi

	echo -n "."
	sleep 0.5
done

echo "Executing \"$ARGS\""
exec $ARGS
