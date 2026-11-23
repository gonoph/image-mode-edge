# Migrating RHEL 9 for Edge to RHEL 9 Image Mode (`bootc`)

This repository documents the migration of an existing **RHEL 9 for Edge** (`rpm-ostree` + Image Builder) deployment pipeline (`CO_Edge_9`) to **RHEL 9 Image Mode** (`bootc` + `bootc-image-builder`).

## Why Migrate to Image Mode?

While RHEL 9 for Edge and RHEL 9 Image Mode share the exact same runtime OSTree filesystem semantics (an atomic, read-only `/usr`, a 3-way merged `/etc`, and a persistent `/var`), moving to Image Mode eliminates the operational overhead of maintaining a dedicated Image Builder compose server and static HTTP OSTree hosting. Instead, the entire operating system is built, versioned, and distributed as a standard OCI container image (`rhel9/rhel-bootc`)—aligning directly with the unified deployment architecture used in **RHEL 10**.

---

## Repository Structure

| File | Description |
| :--- | :--- |
| **`edge9.toml`** | The original Image Builder TOML blueprint (`CO_Edge_9` v0.0.10 targeting `rhel-9.6`). |
| **`ostree.sh`** | Legacy build script invoking `composer-cli compose start-ostree edge9 edge-installer`. |
| **`Containerfile`** | Production RHEL 9.6 Image Mode definition translated from `edge9.toml`, including `greenboot`, `fdo-client`, `clevis`/TPM2, `fapolicyd`, `gnome-kiosk`, and custom registry CA trust. |
| **`Containerfile.edge2bootc`** | Minimal reference `Containerfile` demonstrating how to recreate a baseline RHEL for Edge equivalent (`greenboot` + `fdo-client`) from `rhel9/rhel-bootc`. |
| **`config.toml`** | `bootc-image-builder` customization file enforcing a GPT partition table, UEFI boot layout, and automated Kickstart installation. |
| **`gonoph-ca.crt`** | Custom root CA certificate used to secure the internal lab Docker/OCI container registry. |
| **`im.sh`** | Build script that compiles `Containerfile` with Podman, tags the image, and pushes it to the private registry. |
| **`iso-local.sh`** | Generates a bootable `anaconda-iso` using `bootc-image-builder` and local container storage (`--local`). |
| **`iso-local+satellite.sh`** | *(Untested)* Generates an `anaconda-iso` while mounting the build host's Red Hat Satellite repositories, entitlement certificates, and CA trust into `bootc-image-builder`. |

---

## Key Architectural & Migration Changes

### 1. Blueprint (`edge9.toml`) to `Containerfile`
* **Base Image:** Uses `FROM registry.redhat.io/rhel9/rhel-bootc:9.6` to match `distro = "rhel-9.6"`.
* **Packages & Services:** Blueprint `[[packages]]` entries map 1:1 to `dnf install -y` layers. Because Image Mode images start minimal, graphical targets and security daemons (`graphical.target`, `gdm.service`, `fapolicyd.service`, `clevis-luks-askpass.path`, `rsyslog.service`) are explicitly enabled via `systemctl`.
* **Greenboot & FDO Support:** Unlike `edge-*` composes that bundle `greenboot` automatically, `greenboot`, `greenboot-default-health-checks`, and `fdo-client` are explicitly installed and enabled via `systemctl enable greenboot-healthcheck.service`.
* **Build Validation:** Ends with `RUN bootc container lint` to verify filesystem compliance (such as ensuring no unsupported `/var` mutations or broken symlinks exist) before pushing to the registry.

### 2. Custom Lab Registry CA (`gonoph-ca.crt`)
To ensure deployed edge nodes trust the private registry for future `bootc upgrade` and `bootc switch` operations without TLS errors, `gonoph-ca.crt` is baked directly into the OS image during build:
```dockerfile
COPY gonoph-ca.crt /etc/pki/ca-trust/source/anchors/gonoph-ca.crt
RUN update-ca-trust extract
```
*(Note: The build host must also have `gonoph-ca.crt` installed in `/etc/pki/ca-trust/source/anchors/` with `update-ca-trust` run so `podman push` succeeds.)*

### 3. UEFI + GPT Disk Layout (`config.toml`)
`bootc-image-builder` defaults to GPT and UEFI on `x86_64` and `aarch64`. To prevent Anaconda from falling back to legacy BIOS/MBR partitioning on hardware with CSM enabled, `config.toml` explicitly enforces GPT and UEFI via Kickstart:
```toml
[customizations.installer.kickstart]
contents = """
zerombr
clearpart --all --initlabel --disklabel=gpt
reqpart --add-boot
part / --fstype="xfs" --grow
network --bootproto=dhcp --activate
"""
```

---

## Build & Deployment Workflow

### Prerequisites
* A registered RHEL 9.6 build host (connected to Red Hat CDN or Red Hat Satellite) so Podman automatically mounts `/etc/pki/entitlement` and `/etc/rhsm` during `podman build`.
* `gonoph-ca.crt` trusted on the build host and authenticated via `sudo podman login <registry>`.

### Step 1: Build and Push the Image Mode Container (`im.sh`)
Run `im.sh` as `root` (required so `bootc-image-builder` can access `/var/lib/containers/storage`):
```bash
sudo ./im.sh
```
This builds `Containerfile`, runs `bootc container lint`, tags the image for the private registry, and pushes it.

### Step 2: Generate the Installer ISO (`iso-local.sh`)
Run `iso-local.sh` to invoke `registry.redhat.io/rhel9/bootc-image-builder:9.6` with `--type anaconda-iso` and `--local`:
```bash
sudo ./iso-local.sh
```
* **Why `--local`?** Reading the image from root's local Podman storage embeds the OS payload directly into `./output/bootiso/install.iso`. Anaconda installs directly from the ISO without needing to pull over TLS during installation, while still configuring the installed system's `bootc` origin to point to the remote registry URL.

### Step 3: *(Optional / Untested)* Building the ISO via Satellite (`iso-local+satellite.sh`)
When `bootc-image-builder` builds the Anaconda installer wrapper, its internal OSBuild pipeline pulls installer RPMs (`anaconda`, `lorax`, kernel packages). In disconnected or Satellite-managed environments, `iso-local+satellite.sh` overrides the container's default CDN repos by bind-mounting the build host's Satellite configuration read-only:
* `/etc/yum.repos.d/redhat.repo`
* `/etc/pki/entitlement`
* `/etc/rhsm` (including `/etc/rhsm/ca/katello-server-ca.pem`)
* `/etc/pki/ca-trust`

```bash
sudo ./iso-local+satellite.sh
```

---

## Post-Install Verification

After booting a target VM or edge device from `./output/bootiso/install.iso`, verify the deployment state:

1. **Confirm Image Mode & Registry Origin:**
   ```bash
   sudo bootc status
   sudo bootc upgrade --check
   ```
2. **Confirm UEFI + GPT Boot:**
   ```bash
   [ -d /sys/firmware/efi ] && echo "UEFI" || echo "BIOS"
   lsblk -f
   ```
3. **Confirm Greenboot & Security Services:**
   ```bash
   systemctl status greenboot-healthcheck.service fapolicyd.service gdm.service
   ```

# AI DISCLAIMER

The AI tool, Gemini, helped me convert the toml file to a Containerfile, where I was able to customize it for the current environment and task.

Gemini also assisted me in summarizing the conversation and created this Readme.md
