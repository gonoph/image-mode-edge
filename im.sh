#!/bin/bash

set -x -e
podman login -u biholmes --secret redhat_login registry.redhat.io
podman build -t registry.virt.gonoph.net/edge9:latest .
podman push registry.virt.gonoph.net/edge9:latest
podman rmi registry.virt.gonoph.net/edge9:latest
