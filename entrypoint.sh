#!/bin/bash
set -xue -o pipefail

SSH_PORT=${SSH_PORT:-2222}
ARGS=$@

echo "Docker: $(dockerd --version)"
echo "Kernel: $(/linux/linux --version)"
echo "Rootfs: $(lsb_release -ds)"
echo
echo "Configuration: MEM=$MEM DISK=$DISK"

#start sshd
/usr/sbin/sshd -p ${SSH_PORT} -o "UsePAM no"

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

slirp4netns --target-type=bess /run/slirp4netns-bess.sock >/tmp/slirp4netns-bess.log 2>&1 &
SLIRP_PID=$!
sleep 1
if ! kill -0 $SLIRP_PID 2>/dev/null; then
    echo "slirp4netns failed to start"
    cat /tmp/slirp4netns-bess.log
    exit 1
fi

# Set ownership of /run at runtime since it's a tmpfs
chown -R 1000:3000 /run/ 2>/dev/null || true

/linux/linux rootfstype=hostfs rw vec0:transport=bess,dst=/run/slirp4netns-bess.sock,depth=128,gro=1 mem=$MEM init=/init.sh 2>&1 &
KERNEL_PID=$!

export DOCKER_HOST=tcp://127.0.0.1:2375

echo -n "waiting for dockerd "
while true; do
	if docker version 2>/dev/null >/dev/null; then
		echo ""
		break
	fi
	# Check if kernel is still running
	if ! kill -0 $KERNEL_PID 2>/dev/null; then
		echo ""
		echo "Failed to start UML kernel"
		exit 1
	fi

	echo -n "."
	sleep 0.5
done

echo "Executing \"$ARGS\""
exec $ARGS
