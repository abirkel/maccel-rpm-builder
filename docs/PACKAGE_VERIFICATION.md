# Package Verification and Installation Guide

This guide provides comprehensive instructions for verifying and installing maccel RPM packages built by this repository.

## Package Overview

The maccel-rpm-builder produces two RPM packages:

- **kmod-maccel**: Kernel module package containing the maccel.ko driver
- **maccel**: Userspace package containing CLI tools, udev rules, and configuration

## Package Verification

### Sigstore Keyless Verification (Recommended)

All packages are signed using Sigstore keyless signing for enhanced security and transparency.

#### Install Cosign

```bash
# Download and install cosign
curl -sLO https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
chmod +x cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign

# Verify cosign installation
cosign version
```

#### Download Package and Signatures

```bash
# Set variables for your specific package
RELEASE_TAG="kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0"
PACKAGE_NAME="kmod-maccel-1.0.0-1.fc41.x86_64.rpm"
BASE_URL="https://github.com/USERNAME/maccel-rpm-builder/releases/download"

# Download package and verification files
wget "${BASE_URL}/${RELEASE_TAG}/${PACKAGE_NAME}"
wget "${BASE_URL}/${RELEASE_TAG}/${PACKAGE_NAME}.sig"
wget "${BASE_URL}/${RELEASE_TAG}/${PACKAGE_NAME}.crt"
```

#### Verify Package Signature

```bash
# Verify the package signature
cosign verify-blob \
  --signature "${PACKAGE_NAME}.sig" \
  --certificate "${PACKAGE_NAME}.crt" \
  --certificate-identity-regexp ".*" \
  --certificate-oidc-issuer-regexp ".*" \
  "${PACKAGE_NAME}"
```

**Expected output:**
```
Verified OK
```

### SHA256 Checksum Verification

```bash
# Download checksums file
wget "${BASE_URL}/${RELEASE_TAG}/checksums.txt"

# Verify package checksum
sha256sum -c checksums.txt --ignore-missing
```

**Expected output:**
```
kmod-maccel-1.0.0-1.fc41.x86_64.rpm: OK
maccel-1.0.0-1.fc41.x86_64.rpm: OK
```

### RPM Package Integrity Check

```bash
# Check RPM package integrity
rpm -K "${PACKAGE_NAME}"
```

**Expected output:**
```
kmod-maccel-1.0.0-1.fc41.x86_64.rpm: digests signatures OK
```

### Build Metadata Verification

```bash
# Download and examine build metadata
wget "${BASE_URL}/${RELEASE_TAG}/build-info.json"
cat build-info.json | jq '.'
```

**Example build metadata:**
```json
{
  "kernel_version": "6.11.5-300.fc41.x86_64",
  "maccel_commit": "abc123def456",
  "build_timestamp": "2024-10-28T12:00:00Z",
  "packages": [
    {
      "name": "kmod-maccel",
      "version": "1.0.0-1.fc41",
      "architecture": "x86_64",
      "download_url": "https://github.com/user/maccel-rpm-builder/releases/download/..."
    }
  ]
}
```

## Package Installation

### Prerequisites

Ensure your system meets the requirements:

```bash
# Check Fedora version
cat /etc/fedora-release

# Check kernel version
uname -r

# Ensure kernel headers are available (for kmod package)
sudo dnf install kernel-devel-$(uname -r)
```

### Installation Methods

#### Method 1: Direct RPM Installation

```bash
# Install both packages
sudo rpm -ivh kmod-maccel-*.rpm maccel-*.rpm

# Or install individually
sudo rpm -ivh kmod-maccel-*.rpm
sudo rpm -ivh maccel-*.rpm
```

#### Method 2: DNF Installation (Local Files)

```bash
# Install with dependency resolution
sudo dnf install ./kmod-maccel-*.rpm ./maccel-*.rpm
```

#### Method 3: Blue Build Integration

For Blue Build workflows, add to your recipe:

```yaml
# recipe.yml
name: my-aurora-build
description: Aurora with maccel support
base-image: ghcr.io/ublue-os/aurora
image-version: 41

modules:
  - type: rpm-ostree
    repos:
      # Add any additional repos if needed
    install:
      # Install from URLs
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/kmod-maccel-1.0.0-1.fc41.x86_64.rpm
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/maccel-1.0.0-1.fc41.x86_64.rpm
```

### Post-Installation Verification

#### Verify Package Installation

```bash
# Check installed packages
rpm -qa | grep maccel

# Get package information
rpm -qi kmod-maccel
rpm -qi maccel

# List package files
rpm -ql kmod-maccel
rpm -ql maccel
```

#### Verify Kernel Module

```bash
# Load the kernel module
sudo modprobe maccel

# Check if module is loaded
lsmod | grep maccel

# Check module information
modinfo maccel
```

#### Verify CLI Tools

```bash
# Check CLI installation
which maccel
maccel --version

# Test CLI functionality (requires proper permissions)
maccel --help
```

#### Verify Udev Rules

```bash
# Check udev rules installation
ls -la /etc/udev/rules.d/99-maccel.rules

# Check maccel group creation
getent group maccel

# Add user to maccel group (if needed)
sudo usermod -a -G maccel $USER
```

### Troubleshooting Installation

#### Common Installation Issues

**Problem**: Dependency conflicts
```
Error: package conflicts with...
```

**Solution**:
```bash
# Check for conflicting packages
rpm -qa | grep -i mouse
rpm -qa | grep -i accel

# Remove conflicting packages if safe
sudo rpm -e conflicting-package
```

**Problem**: Kernel module won't load
```
modprobe: ERROR: could not insert 'maccel': Operation not permitted
```

**Solution**:
```bash
# Check if Secure Boot is enabled
mokutil --sb-state

# If Secure Boot is enabled, you may need to sign the module
# or disable Secure Boot temporarily for testing

# Check kernel logs for more details
sudo dmesg | grep maccel
```

**Problem**: Permission denied accessing devices
```
maccel: Permission denied
```

**Solution**:
```bash
# Ensure user is in maccel group
groups $USER

# Add user to maccel group
sudo usermod -a -G maccel $USER

# Log out and back in, or use newgrp
newgrp maccel

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

#### Verification Commands

```bash
# Complete system verification
echo "=== Package Verification ==="
rpm -qa | grep maccel

echo "=== Kernel Module Status ==="
lsmod | grep maccel || echo "Module not loaded"

echo "=== CLI Tool Status ==="
which maccel && maccel --version || echo "CLI not found"

echo "=== Udev Rules Status ==="
ls -la /etc/udev/rules.d/99-maccel.rules || echo "Udev rules not found"

echo "=== Group Membership ==="
groups $USER | grep maccel && echo "User in maccel group" || echo "User not in maccel group"

echo "=== Device Access ==="
ls -la /dev/input/mice || echo "No mouse devices found"
```

## Uninstallation

### Remove Packages

```bash
# Stop any running maccel processes
sudo pkill maccel

# Unload kernel module
sudo modprobe -r maccel

# Remove packages
sudo rpm -e maccel kmod-maccel

# Clean up any remaining files (optional)
sudo rm -f /etc/udev/rules.d/99-maccel.rules
sudo groupdel maccel 2>/dev/null || true
```

### Verify Removal

```bash
# Check packages are removed
rpm -qa | grep maccel

# Check module is unloaded
lsmod | grep maccel

# Check files are removed
ls -la /etc/udev/rules.d/99-maccel.rules
```

## Integration Examples

### Blue Build Workflow Integration

#### Automatic Package Detection

```yaml
# .github/workflows/build.yml
name: Build Aurora with maccel

on:
  push:
    branches: [main]
  schedule:
    - cron: '0 6 * * *'  # Daily builds

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Get Aurora kernel version
        id: kernel
        run: |
          # Extract kernel version from Aurora base image
          KERNEL_VERSION=$(skopeo inspect docker://ghcr.io/ublue-os/aurora:41 | \
            jq -r '.Labels["ostree.linux"]')
          echo "version=${KERNEL_VERSION}" >> $GITHUB_OUTPUT

      - name: Trigger maccel RPM build
        run: |
          gh api repos/USERNAME/maccel-rpm-builder/dispatches \
            --method POST \
            --field event_type=build-for-kernel \
            --field client_payload="{\"kernel_version\":\"${{ steps.kernel.outputs.version }}\",\"fedora_version\":\"41\",\"trigger_repo\":\"${{ github.repository }}\"}"
        env:
          GITHUB_TOKEN: ${{ secrets.DISPATCH_TOKEN }}

      - name: Wait for build completion
        run: |
          # Wait for build to complete and get package URLs
          # Implementation depends on your specific needs
```

#### Manual Package URLs

```yaml
# recipe.yml with specific package versions
modules:
  - type: rpm-ostree
    install:
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/kmod-maccel-1.0.0-1.fc41.x86_64.rpm
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/maccel-1.0.0-1.fc41.x86_64.rpm
```

### Container Integration

#### Dockerfile Example

```dockerfile
FROM fedora:41

# Install packages from GitHub releases
RUN curl -L -o kmod-maccel.rpm \
    "https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/kmod-maccel-1.0.0-1.fc41.x86_64.rpm" && \
    curl -L -o maccel.rpm \
    "https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/maccel-1.0.0-1.fc41.x86_64.rpm" && \
    dnf install -y ./kmod-maccel.rpm ./maccel.rpm && \
    rm -f *.rpm
```

#### Podman/Docker Usage

```bash
# Build container with maccel
podman build -t my-fedora-maccel .

# Run with device access
podman run -it --privileged --device /dev/input my-fedora-maccel

# Test maccel functionality
podman exec -it container_name maccel --version
```

## Security Considerations

### Package Verification Best Practices

1. **Always verify signatures** before installation
2. **Check checksums** to ensure package integrity
3. **Review build metadata** to understand package provenance
4. **Use HTTPS URLs** for all downloads
5. **Verify package sources** match expected repositories

### Secure Installation

```bash
# Download verification script
curl -sL https://raw.githubusercontent.com/USERNAME/maccel-rpm-builder/main/scripts/verify-packages.sh -o verify-packages.sh
chmod +x verify-packages.sh

# Use script to verify and install
./verify-packages.sh install kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0
```

### Audit Trail

Keep records of installed packages:

```bash
# Create installation log
echo "$(date): Installed maccel packages" >> /var/log/maccel-install.log
rpm -qa | grep maccel >> /var/log/maccel-install.log
```

## Support and Resources

### Documentation Links
- [maccel upstream documentation](https://github.com/Gnarus-G/maccel)
- [Blue Build documentation](https://blue-build.org/)
- [Fedora RPM packaging guidelines](https://docs.fedoraproject.org/en-US/packaging-guidelines/)

### Getting Help
- Report package issues: [maccel-rpm-builder issues](https://github.com/USERNAME/maccel-rpm-builder/issues)
- maccel functionality: [maccel issues](https://github.com/Gnarus-G/maccel/issues)
- Blue Build integration: [Blue Build community](https://blue-build.org/community/)

### Useful Commands Reference

```bash
# Package management
rpm -qa | grep maccel          # List installed maccel packages
rpm -qi package-name           # Get package information
rpm -ql package-name           # List package files
rpm -V package-name            # Verify package files

# Kernel module management
modprobe maccel                # Load module
modprobe -r maccel             # Unload module
lsmod | grep maccel            # Check if loaded
modinfo maccel                 # Get module info

# System verification
uname -r                       # Check kernel version
cat /etc/fedora-release        # Check Fedora version
groups $USER                   # Check user groups
ls -la /dev/input/             # Check input devices
```