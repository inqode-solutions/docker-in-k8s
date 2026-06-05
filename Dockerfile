ARG DEBIAN_VERSION=13.5
ARG KERNEL_VERSION=5.15
ARG GOLANG_VERSION=1.17.6
ARG DOCKER_CHANNEL=stable
ARG DOCKER_VERSION=5:29.1.5-1~debian.13~trixie
ARG SLIRP4NETNS_VERSION=1.2.0-beta.0

FROM debian:$DEBIAN_VERSION AS kernel_build

RUN \
	apt-get update && \
	apt-get install git fakeroot build-essential ncurses-dev xz-utils libssl-dev bc wget flex bison libelf-dev -y && \
	apt-get install -y --no-install-recommends libarchive-tools

ARG KERNEL_VERSION

RUN \
	wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$KERNEL_VERSION.tar.xz && \
	tar -xf linux-$KERNEL_VERSION.tar.xz && \
	rm linux-$KERNEL_VERSION.tar.xz

WORKDIR linux-$KERNEL_VERSION
COPY KERNEL.config .config
RUN make ARCH=um oldconfig && make ARCH=um prepare
RUN make ARCH=um -j `nproc`
RUN mkdir /out && cp -f linux /out/linux

RUN cp .config /KERNEL.config

# usage: docker build -t foo --target print_config . && docker run -it --rm foo > KERNEL.config
FROM debian:$DEBIAN_VERSION AS print_config
COPY --from=kernel_build /KERNEL.config /KERNEL.CONFIG
CMD ["cat", "/KERNEL.CONFIG"]

FROM golang:$GOLANG_VERSION AS diuid-docker-proxy
COPY diuid-docker-proxy /go/src/github.com/weber-software/diuid/diuid-docker-proxy
WORKDIR /go/src/github.com/weber-software/diuid/diuid-docker-proxy
RUN go build -o /diuid-docker-proxy

FROM debian:$DEBIAN_VERSION

LABEL maintainer="weber@weber-software.com"

RUN \
	apt-get update && \
	apt-get install -y wget net-tools openssh-server psmisc rng-tools \
	apt-transport-https ca-certificates gnupg2 lsb-release iptables iproute2

RUN \
	update-alternatives --set iptables /usr/sbin/iptables-legacy && \
	update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

#install docker
ARG DOCKER_CHANNEL
ARG DOCKER_VERSION
RUN \
    mkdir -p /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/docker.gpg https://download.docker.com/linux/debian/gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) $DOCKER_CHANNEL" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-cache madison docker-ce && \
    apt-get install -y docker-ce=$DOCKER_VERSION docker-ce-cli=$DOCKER_VERSION containerd.io

#install diuid-docker-proxy
COPY --from=diuid-docker-proxy /diuid-docker-proxy /usr/bin

#install slirp4netns (used by UML)
ARG SLIRP4NETNS_VERSION
RUN \
  wget -O /usr/bin/slirp4netns https://github.com/rootless-containers/slirp4netns/releases/download/v${SLIRP4NETNS_VERSION}/slirp4netns-x86_64 && \
  chmod +x /usr/bin/slirp4netns

#install kernel and scripts
COPY --from=kernel_build /out/linux /linux/linux
ADD entrypoint.sh entrypoint.sh
ADD init.sh init.sh

#specify the of memory that the uml kernel can use 
ENV MEM=2G
ENV TMPDIR=/umlshm
ENV DISK=10G

RUN \
	chmod og+r /etc/ssh/ssh_host_rsa_key && \
	addgroup --gid 3000 user && \
	adduser --uid 1000 --gid 3000 user && \
	mkdir -p /var/lib/docker/ && \
	mkdir -p /persistent/ && \
	mkdir -p /etc/docker/ && \
	chown -R 1000:3000 /persistent/ && \
	chown -R 1000:3000 /run/ && \
	chown -R 1000:3000 /etc/docker/

#it is recommended to override /umlshm with
#--tmpfs /umlshm:rw,nosuid,nodev,exec,size=8g
VOLUME /umlshm

#disk image for /var/lib/docker is created under this directory
VOLUME /persistent

USER 1000:3000

RUN \
	mkdir ~/.ssh && \
	ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N "" && \
	cp ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "bash" ]
