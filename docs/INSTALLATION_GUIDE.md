# maccel Installation Guide

This guide provides step-by-step installation instructions for maccel RPM packages in different environments and use cases.

## Quick Start

### For Blue Build Users

If you're using Blue Build to create custom Fedora images, add maccel packages to your recipe:

```yaml
# recipe.yml
name: my-aurora-maccel
description: Aurora with maccel mouse acceleration
base-image: ghcr.io/ublue-os/aurora
image-version: 41

modules:
  - type: rpm-ostree
    install:
      # Replace USERNAME and versions with actual values
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/kmod-maccel-1.0.0-1.fc41.x86_64.rpm
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/maccel-1.0.0-1.fc41.x86_64.rpm
```

### For Standard Fedora Users

```bash
# 1. Find your kernel version
KERNEL_VERSION=$(uname -r)
echo "Your kernel version: $KERNEL_VERSION"

# 2. Download packages for your kernel version
# (Replace USERNAME and check available releases)
wget https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-${KERNEL_VERSION}-maccel-1.0.0/kmod-maccel-1.0.0-1.fc41.x86_64.rpm
wget https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-${KERNEL_VERSION}-maccel-1.0.0/maccel-1.0.0-1.fc41.x86_64.rpm

# 3. Install packages
sudo dnf install ./kmod-maccel-*.rpm ./maccel-*.rpm

# 4. Load kernel module and test
sudo modprobe maccel
maccel --version
```

## Detailed Installation Instructions

### Step 1: System Requirements

#### Check System Compatibility

```bash
# Check Fedora version (supported: 40, 41+)
cat /etc/fedora-release

# Check architecture (supported: x86_64)
uname -m

# Check kernel version
uname -r
```

#### Install Prerequisites

```bash
# Install kernel development headers (required for kmod package)
sudo dnf install kernel-devel-$(uname -r)

# Install verification tools (optional but recommended)
sudo dnf install rpm-sign cosign

# Ensure user can access input devices
sudo usermod -a -G input $USER
```

### Step 2: Find Available Packages

#### Method 1: Browse GitHub Releases

1. Visit: `https://github.com/USERNAME/maccel-rpm-builder/releases`
2. Look for releases matching your kernel version
3. Download both `kmod-maccel` and `maccel` packages

#### Method 2: Use Detection Script

```bash
# Clone repository for tools
git clone https://github.com/USERNAME/maccel-rpm-builder.git
cd maccel-rpm-builder

# Check available packages for your kernel
./scripts/check-existing-packages.sh check $(uname -r)

# Get download URLs
./scripts/check-existing-packages.sh info $(uname -r)
```

#### Method 3: API Query

```bash
# Get latest release for your kernel version
KERNEL_VERSION=$(uname -r)
gh api repos/USERNAME/maccel-rpm-builder/releases | \
  jq -r ".[] | select(.tag_name | contains(\"kernel-${KERNEL_VERSION}\")) | .tag_name" | \
  head -1
```

### Step 3: Download and Verify Packages

#### Download Packages

```bash
# Set variables (replace with actual values)
RELEASE_TAG="kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0"
BASE_URL="https://github.com/USERNAME/maccel-rpm-builder/releases/download"

# Download both packages
wget "${BASE_URL}/${RELEASE_TAG}/kmod-maccel-1.0.0-1.fc41.x86_64.rpm"
wget "${BASE_URL}/${RELEASE_TAG}/maccel-1.0.0-1.fc41.x86_64.rpm"

# Download verification files
wget "${BASE_URL}/${RELEASE_TAG}/checksums.txt"
wget "${BASE_URL}/${RELEASE_TAG}/kmod-maccel-1.0.0-1.fc41.x86_64.rpm.sig"
wget "${BASE_URL}/${RELEASE_TAG}/maccel-1.0.0-1.fc41.x86_64.rpm.sig"
```

#### Verify Package Integrity

```bash
# Verify checksums
sha256sum -c checksums.txt --ignore-missing

# Verify RPM integrity
rpm -K *.rpm
```

### Step 4: Install Packages

#### Option A: DNF Installation (Recommended)

```bash
# Install with dependency resolution
sudo dnf install ./kmod-maccel-*.rpm ./maccel-*.rpm
```

#### Option B: RPM Installation

```bash
# Install kernel module package first
sudo rpm -ivh kmod-maccel-*.rpm

# Install userspace package
sudo rpm -ivh maccel-*.rpm
```

#### Option C: Upgrade Existing Installation

```bash
# Upgrade packages if already installed
sudo dnf upgrade ./kmod-maccel-*.rpm ./maccel-*.rpm
```

### Step 5: Post-Installation Setup

#### Load Kernel Module

```bash
# Load the maccel kernel module
sudo modprobe maccel

# Verify module is loaded
lsmod | grep maccel

# Enable automatic loading at boot
echo "maccel" | sudo tee /etc/modules-load.d/maccel.conf
```

#### Configure User Permissions

```bash
# Add user to maccel group
sudo usermod -a -G maccel $USER

# Log out and back in, or use newgrp
newgrp maccel

# Verify group membership
groups $USER | grep maccel
```

#### Reload Udev Rules

```bash
# Reload udev rules for device access
sudo udevadm control --reload-rules
sudo udevadm trigger

# Verify udev rules are installed
ls -la /etc/udev/rules.d/99-maccel.rules
```

### Step 6: Test Installation

#### Basic Functionality Test

```bash
# Test CLI tool
maccel --version
maccel --help

# Check kernel module info
modinfo maccel

# Test device access (should not show permission errors)
maccel list-devices 2>/dev/null && echo "Device access OK" || echo "Check permissions"
```

#### Advanced Testing

```bash
# Test configuration
maccel config --show

# Test mouse detection
maccel detect

# Test acceleration (if mouse is connected)
maccel set-accel 1.5
```

## Installation Use Cases

### Use Case 1: Blue Build Integration

#### Automatic Package Detection

Create a Blue Build workflow that automatically detects and uses the latest packages:

```yaml
# .github/workflows/build-aurora.yml
name: Build Aurora with maccel

on:
  push:
    branches: [main]
  schedule:
    - cron: '0 6 * * *'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Get Aurora kernel version
        id: kernel
        run: |
          # Get kernel version from Aurora base image
          KERNEL_VERSION=$(skopeo inspect docker://ghcr.io/ublue-os/aurora:41 | \
            jq -r '.Labels["ostree.linux"]')
          echo "version=${KERNEL_VERSION}" >> $GITHUB_OUTPUT
          
      - name: Trigger maccel build
        run: |
          gh api repos/USERNAME/maccel-rpm-builder/dispatches \
            --method POST \
            --field event_type=build-for-kernel \
            --field client_payload="{\"kernel_version\":\"${{ steps.kernel.outputs.version }}\",\"fedora_version\":\"41\",\"trigger_repo\":\"${{ github.repository }}\"}"
        env:
          GITHUB_TOKEN: ${{ secrets.DISPATCH_TOKEN }}
          
      - name: Get package URLs
        id: packages
        run: |
          # Note: Build typically completes in 5-10 minutes
          # Poll for release or check workflow status before proceeding
          RELEASE_TAG="kernel-${{ steps.kernel.outputs.version }}-maccel-latest"
          echo "kmod_url=https://github.com/USERNAME/maccel-rpm-builder/releases/download/${RELEASE_TAG}/kmod-maccel-latest.rpm" >> $GITHUB_OUTPUT
          echo "maccel_url=https://github.com/USERNAME/maccel-rpm-builder/releases/download/${RELEASE_TAG}/maccel-latest.rpm" >> $GITHUB_OUTPUT
          
      - name: Update recipe
        run: |
          # Update recipe.yml with new package URLs
          sed -i "s|kmod-maccel.*rpm|${{ steps.packages.outputs.kmod_url }}|" recipe.yml
          sed -i "s|maccel.*rpm|${{ steps.packages.outputs.maccel_url }}|" recipe.yml
          
      - name: Build image
        uses: blue-build/github-action@v1
```

#### Static Package URLs

For stable builds, use specific package versions:

```yaml
# recipe.yml
name: aurora-maccel-stable
description: Aurora with stable maccel version
base-image: ghcr.io/ublue-os/aurora
image-version: 41

modules:
  - type: rpm-ostree
    install:
      # Use specific, tested versions
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/kmod-maccel-1.0.0-1.fc41.x86_64.rpm
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/maccel-1.0.0-1.fc41.x86_64.rpm
```

### Use Case 2: Development Environment

#### Local Development Setup

```bash
# Clone maccel-rpm-builder for tools
git clone https://github.com/USERNAME/maccel-rpm-builder.git
cd maccel-rpm-builder

# Install development dependencies
sudo dnf install rpm-build kernel-devel rust cargo

# Build packages locally (optional)
./scripts/build-packages.sh $(uname -r) 41

# Or download pre-built packages
./scripts/check-existing-packages.sh info $(uname -r)
```

#### Testing Different Versions

```bash
# Test with specific maccel version
MACCEL_VERSION="1.0.0"
./scripts/detect-maccel-version.sh $MACCEL_VERSION

# Build for different kernel version
KERNEL_VERSION="6.10.12-200.fc40.x86_64"
./scripts/build-packages.sh $KERNEL_VERSION 40
```

### Use Case 3: Container Integration

#### Dockerfile Integration

```dockerfile
FROM fedora:41

# Install maccel packages
ARG KERNEL_VERSION=6.11.5-300.fc41.x86_64
ARG MACCEL_VERSION=1.0.0
ARG RELEASE_TAG=kernel-${KERNEL_VERSION}-maccel-${MACCEL_VERSION}
ARG BASE_URL=https://github.com/USERNAME/maccel-rpm-builder/releases/download

RUN dnf install -y \
    ${BASE_URL}/${RELEASE_TAG}/kmod-maccel-${MACCEL_VERSION}-1.fc41.x86_64.rpm \
    ${BASE_URL}/${RELEASE_TAG}/maccel-${MACCEL_VERSION}-1.fc41.x86_64.rpm && \
    dnf clean all

# Configure maccel
RUN echo "maccel" > /etc/modules-load.d/maccel.conf
```

#### Podman/Docker Usage

```bash
# Build container
podman build --build-arg KERNEL_VERSION=$(uname -r) -t fedora-maccel .

# Run with device access
podman run -it --privileged \
  --device /dev/input \
  --volume /lib/modules:/lib/modules:ro \
  fedora-maccel

# Test maccel in container
podman exec -it container_name maccel --version
```

### Use Case 4: Automated Deployment

#### Ansible Playbook

```yaml
# playbook.yml
---
- name: Install maccel on Fedora systems
  hosts: fedora_systems
  become: yes
  vars:
    kernel_version: "{{ ansible_kernel }}"
    maccel_version: "1.0.0"
    
  tasks:
    - name: Get package URLs
      uri:
        url: "https://api.github.com/repos/USERNAME/maccel-rpm-builder/releases"
        method: GET
      register: releases
      
    - name: Find matching release
      set_fact:
        release_tag: "{{ item.tag_name }}"
      loop: "{{ releases.json }}"
      when: item.tag_name is search(kernel_version)
      
    - name: Install maccel packages
      dnf:
        name:
          - "https://github.com/USERNAME/maccel-rpm-builder/releases/download/{{ release_tag }}/kmod-maccel-{{ maccel_version }}-1.fc41.x86_64.rpm"
          - "https://github.com/USERNAME/maccel-rpm-builder/releases/download/{{ release_tag }}/maccel-{{ maccel_version }}-1.fc41.x86_64.rpm"
        state: present
        
    - name: Load kernel module
      modprobe:
        name: maccel
        state: present
        
    - name: Add users to maccel group
      user:
        name: "{{ item }}"
        groups: maccel
        append: yes
      loop: "{{ maccel_users | default([]) }}"
```

#### Systemd Service

```ini
# /etc/systemd/system/maccel-setup.service
[Unit]
Description=maccel Mouse Acceleration Setup
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/modprobe maccel
ExecStart=/usr/bin/udevadm control --reload-rules
ExecStart=/usr/bin/udevadm trigger
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
# Enable service
sudo systemctl enable maccel-setup.service
sudo systemctl start maccel-setup.service
```

## Troubleshooting Common Installation Issues

### Issue 1: Package Not Found

**Problem**: No packages available for your kernel version

**Solution**:
```bash
# Check available releases
gh api repos/USERNAME/maccel-rpm-builder/releases | jq -r '.[].tag_name'

# Trigger build for your kernel version
gh api repos/USERNAME/maccel-rpm-builder/dispatches \
  --method POST \
  --field event_type=build-for-kernel \
  --field client_payload="{\"kernel_version\":\"$(uname -r)\",\"fedora_version\":\"41\",\"trigger_repo\":\"manual\"}"
```

### Issue 2: Dependency Conflicts

**Problem**: RPM dependency conflicts during installation

**Solution**:
```bash
# Check for conflicting packages
rpm -qa | grep -E "(mouse|accel|input)"

# Use DNF to resolve dependencies
sudo dnf install --allowerasing ./kmod-maccel-*.rpm ./maccel-*.rpm

# Or force installation (use with caution)
sudo rpm -ivh --force --nodeps *.rpm
```

### Issue 3: Kernel Module Loading Fails

**Problem**: `modprobe maccel` fails

**Solution**:
```bash
# Check kernel version compatibility
uname -r
rpm -qi kmod-maccel | grep Version

# Check for Secure Boot issues
mokutil --sb-state

# Check kernel logs
sudo dmesg | grep maccel

# Rebuild module for current kernel (if needed)
sudo dkms autoinstall
```

### Issue 4: Permission Issues

**Problem**: maccel command shows permission denied

**Solution**:
```bash
# Check group membership
groups $USER

# Add to maccel group
sudo usermod -a -G maccel $USER

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Check device permissions
ls -la /dev/input/

# Test with sudo (temporary)
sudo maccel --version
```

## Maintenance and Updates

### Checking for Updates

```bash
# Check current installed version
rpm -qi maccel | grep Version

# Check for newer releases
gh api repos/USERNAME/maccel-rpm-builder/releases/latest | jq -r '.tag_name'

# Compare with your kernel version
echo "Current kernel: $(uname -r)"
```

### Updating Packages

```bash
# Download newer packages
KERNEL_VERSION=$(uname -r)
# ... download commands ...

# Update packages
sudo dnf upgrade ./kmod-maccel-*.rpm ./maccel-*.rpm

# Reload kernel module
sudo modprobe -r maccel
sudo modprobe maccel
```

### Automated Update Script

```bash
#!/bin/bash
# update-maccel.sh

KERNEL_VERSION=$(uname -r)
REPO="USERNAME/maccel-rpm-builder"

# Get latest release for current kernel
LATEST_RELEASE=$(gh api repos/$REPO/releases | \
  jq -r ".[] | select(.tag_name | contains(\"kernel-${KERNEL_VERSION}\")) | .tag_name" | \
  head -1)

if [ -n "$LATEST_RELEASE" ]; then
    echo "Found release: $LATEST_RELEASE"
    
    # Download and install
    BASE_URL="https://github.com/$REPO/releases/download"
    wget "${BASE_URL}/${LATEST_RELEASE}/kmod-maccel-"*.rpm
    wget "${BASE_URL}/${LATEST_RELEASE}/maccel-"*.rpm
    
    sudo dnf upgrade ./kmod-maccel-*.rpm ./maccel-*.rpm
    
    # Reload module
    sudo modprobe -r maccel 2>/dev/null || true
    sudo modprobe maccel
    
    echo "maccel updated successfully"
else
    echo "No packages found for kernel version: $KERNEL_VERSION"
fi
```

## Support and Resources

### Getting Help

- **Installation issues**: [Create an issue](https://github.com/USERNAME/maccel-rpm-builder/issues)
- **maccel functionality**: [maccel repository](https://github.com/Gnarus-G/maccel/issues)
- **Blue Build integration**: [Blue Build documentation](https://blue-build.org/)

### Useful Resources

- [Fedora RPM documentation](https://docs.fedoraproject.org/en-US/quick-docs/getting-started-with-rpm/)
- [Kernel module management](https://docs.fedoraproject.org/en-US/fedora/latest/system-administrators-guide/kernel-module-driver-configuration/)
- [Udev rules documentation](https://www.freedesktop.org/software/systemd/man/udev.html)

### Community

- [Blue Build Discord](https://discord.gg/blue-build)
- [Universal Blue community](https://universal-blue.org/)
- [Fedora community](https://fedoraproject.org/wiki/Communicating_and_getting_help)