# Base RHEL 9.6 bootc image matching distro = "rhel-9.6"
FROM registry.redhat.io/rhel9/rhel-bootc:9.6

LABEL name="CO_Edge_9" \
      description="prod_edge_blueprint" \
      version="0.0.10"

# Install packages from blueprint
RUN dnf install -y \
    abattis-cantarell-fonts \
    aide \
    ansible-core \
    audispd-plugins \
    clevis \
    clevis-luks \
    clevis-pin-tpm2 \
    clevis-systemd \
    clevis-udisks2 \
    fapolicyd \
    fapolicyd-selinux \
    gdm \
    glibc-langpack-en \
    gnome-kiosk \
    gnome-kiosk-script-session \
    gnome-terminal \
    insights-client \
    libXScrnSaver \
    logrotate \
    nss-tools \
    rhc \
    rhc-worker-playbook \
    rpm-plugin-fapolicyd \
    rsyslog \
    subscription-manager \
    subscription-manager-plugin-ostree \
    urw-base35-fonts \
    usbutils \
    xorg-x11-fonts-Type1 \
    xorg-x11-server-Xorg \
    && dnf clean all

# Install greenboot (with default health checks) and FDO client support
RUN dnf install -y \
    fdo-client \
    greenboot \
    greenboot-default-health-checks && \
    dnf clean all && \
    systemctl enable greenboot-healthcheck.service

# Enable graphical target and display manager for gnome-kiosk / gdm
RUN systemctl set-default graphical.target && \
    systemctl enable gdm.service

# Enable security, logging, and disk unlock services
RUN systemctl enable \
    clevis-luks-askpass.path \
    fapolicyd.service \
    rsyslog.service

# START MY CUSTOM SCRIPTS
RUN dnf install -y iproute iptables-nft iputils less lvm2 vim rsync sos sudo tmux firewalld \
	&& dnf clean all \
	&& systemctl enable sshd firewalld \
        && firewall-offline-cmd --add-service ssh
RUN sed -i 's/^CREATE_MAIL_SPOOL=yes/CREATE_MAIL_SPOOL=no/' /etc/default/useradd \
        && useradd -m -G wheel gonoph \
        && useradd -m -G wheel ansible \
        && ln -s ../usr/share/zoneinfo/America/New_York /etc/localtime \
        && rp=$(realpath /root) \
        && mkdir -vp $rp \
        && id
COPY <<__SUDO__ /etc/sudoers.d/90-ansible-user
# created by build system
ansible ALL=(ALL) NOPASSWD:ALL
__SUDO__
COPY <<__SUDO__ /etc/sudoers.d/90-gonoph-user
# created by build system
gonoph ALL=(ALL) NOPASSWD:ALL
__SUDO__

# get my internal certs and ssh keys
RUN curl http://zfs1.virt.gonoph.net/scripts/certs.sh | bash \
        && curl https://zfs1.virt.gonoph.net/scripts/ssh.sh | bash

# END MY CUSTOM SCRIPTS

# Validate image compliance for bootc deployment
RUN bootc container lint
