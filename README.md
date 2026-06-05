# Docker in User Mode Linux

An image for running a dockerd inside a user mode linux kernel.
This way it is possible to run and build docker images without forwarding the docker socket or using privileged flags.

## How it works

It starts a user mode linux kernel with a dockerd inside.
The network communication is bridged by slirp.

## Example

`docker run -it --rm --tmpfs /umlshm:rw,nosuid,nodev,exec,size=8g ghcr.io/inqode-solutions/docker-in-k8s:master docker info`

To configure memory size and `/var/lib/docker` size:

`docker run -it --rm -e MEM=4G -e DISK=20G --tmpfs /umlshm:rw,nosuid,nodev,exec,size=8g ghcr.io/inqode-solutions/docker-in-k8s:master docker info`

To preserve `/var/lib/docker` disk:

`docker run -it --rm -v /somewhere:/persistent --tmpfs /umlshm:rw,nosuid,nodev,exec,size=8g ghcr.io/inqode-solutions/docker-in-k8s:master docker info`

To run as a non-root user:

`docker run --user 1000:3000 -it --rm --tmpfs /umlshm:rw,nosuid,nodev,exec,size=8g ghcr.io/inqode-solutions/docker-in-k8s:master docker info`

## Kubernetes Sidecar

This image can be used as a sidecar container in a Kubernetes pod to provide Docker-in-Docker capabilities. This allows your main application containers to build and run Docker images without requiring privileged access to the host Docker socket.

Example pod configuration:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: docker-in-k8s-pod
spec:
  containers:
    - name: app
      image: your-app-image
      env:
        - name: DOCKER_HOST
          value: "tcp://localhost:2375"
    - name: docker-in-uml
      image: ghcr.io/inqode-solutions/docker-in-k8s:master
      args: ["--tmpfs", "/umlshm:rw,nosuid,nodev,exec,size=8g"]
      ports:
        - containerPort: 2375
```
