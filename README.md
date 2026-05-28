# Docker in User Mode Linux

An image for running a dockerd inside a user mode linux kernel.
This way it is possible to run and build docker images without forwarding the docker socket or using privileged flags.
Therefore this image can be used to build docker images with the gitlab-ci-multi-runner docker executor.

## How it works

It starts a user mode linux kernel with a dockerd inside.
The network communication is bridged by slirp.

## Example

`docker run -it --rm weberlars/diuid docker info`

For better performance, mount a tmpfs with exec access on `/umlshm`:

`docker run -it --rm --tmpfs /umlshm:rw,nosuid,nodev,exec,size=8g weberlars/diuid docker info`

To configure memory size and `/var/lib/docker` size:

`docker run -it --rm -e MEM=4G -e DISK=20G weberlars/diuid docker info`

To preserve `/var/lib/docker` disk:

`docker run -it --rm -v /somewhere:/persistent weberlars/diuid docker info`

To run as a non-root user:

`docker run --user 1000:3000 -it --rm weberlars/diuid docker info`
