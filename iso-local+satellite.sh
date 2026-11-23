#!/bin/bash

mkdir -p ./output

sudo podman pull registry.virt.gonoph.net/edge9:latest
sudo podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v ./config.toml:/config.toml:ro \
    -v ./output:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    -v /etc/yum.repos.d/redhat.repo:/etc/yum.repos.d/redhat.repo:ro \
    -v /etc/pki/entitlement:/etc/pki/entitlement:ro \
    -v /etc/rhsm:/etc/rhsm:ro \
    -v /etc/pki/ca-trust:/etc/pki/ca-trust:ro \
    registry.redhat.io/rhel9/bootc-image-builder:9.6 \
    --type anaconda-iso \
    --local \
    --progress=verbose \
    registry.virt.gonoph.net/edge9:latest
