# maccel-rpm-builder

Automated RPM package builder for the [maccel mouse acceleration driver](https://github.com/Gnarus-G/maccel).

## Overview

This repository creates proper RPM packages for maccel on-demand, triggered by Blue Build workflows. It produces two packages:

- **kmod-maccel**: Kernel module package compiled for specific kernel versions
- **maccel**: Userspace CLI tools and configuration files

## Usage

### Repository Dispatch Trigger

Send a repository dispatch event to trigger package building:

```bash
gh api repos/USERNAME/maccel-rpm-builder/dispatches \
  --method POST \
  --field event_type=build-for-kernel \
  --field client_payload='{"kernel_version":"6.11.5-300.fc41.x86_64","fedora_version":"41","trigger_repo":"MyProject"}'
```

### Manual Trigger

Use the GitHub Actions web interface or CLI:

```bash
gh workflow run build-rpm.yml \
  --field kernel_version="6.11.5-300.fc41.x86_64" \
  --field fedora_version="41"
```

## Package Downloads

Packages are published to GitHub Releases with the naming format:
- Release: `kernel-{KERNEL_VERSION}-maccel-{MACCEL_VERSION}`
- Packages: `{package-name}-{version}-{release}.fc{N}.{arch}.rpm`

Example download URLs:
```
https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/kmod-maccel-1.0.0-1.fc41.x86_64.rpm
https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/maccel-1.0.0-1.fc41.x86_64.rpm
```

## Efficiency Features

- **Smart caching**: Skips builds if packages already exist for the kernel version
- **Source change detection**: Compares maccel source commit hashes to avoid unnecessary rebuilds
- **Version detection**: Automatically detects latest maccel version from upstream
- **Build optimization**: Caches dependencies between builds
- **Existing package detection**: Returns URLs to existing packages when builds are skipped

## Integration

This builder is designed to integrate with Blue Build workflows. See the [MyAuroraBluebuild](https://github.com/USERNAME/MyAuroraBluebuild) project for usage examples.

## Repository Dispatch Payload

```json
{
  "event_type": "build-for-kernel",
  "client_payload": {
    "kernel_version": "6.11.5-300.fc41.x86_64",
    "fedora_version": "41",
    "trigger_repo": "MyAuroraBluebuild",
    "force_rebuild": false
  }
}
```

### Force Rebuild

Set `force_rebuild: true` to rebuild packages even if they already exist for the kernel version. This is useful when you need to rebuild with updated dependencies or build environment changes.

## Package Detection

The system includes intelligent package detection that:

1. **Checks for existing releases** matching the kernel version and maccel version
2. **Compares source commit hashes** to detect if maccel source code has changed
3. **Skips unnecessary builds** and returns existing package URLs
4. **Provides detailed package information** including download URLs and metadata

### Manual Package Detection

You can manually check for existing packages using the detection script:

```bash
# Check if packages exist for a kernel version
./scripts/check-existing-packages.sh check 6.11.5-300.fc41.x86_64

# Get information about existing packages
./scripts/check-existing-packages.sh info 6.11.5-300.fc41.x86_64

# List all releases for a kernel version pattern
./scripts/check-existing-packages.sh list 6.11.5-300.fc41.x86_64

# Generate release tag name
./scripts/check-existing-packages.sh release-tag 6.11.5-300.fc41.x86_64 1.0.0
```

## Package Verification

All packages are signed using **Sigstore keyless signing** for enhanced security and transparency.

### Quick Verification

```bash
# Install cosign (Sigstore CLI)
curl -sLO https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
chmod +x cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign

# Download and verify a package
wget https://github.com/USERNAME/maccel-rpm-builder/releases/download/RELEASE_TAG/kmod-maccel-VERSION.rpm
wget https://github.com/USERNAME/maccel-rpm-builder/releases/download/RELEASE_TAG/kmod-maccel-VERSION.rpm.sig
wget https://github.com/USERNAME/maccel-rpm-builder/releases/download/RELEASE_TAG/kmod-maccel-VERSION.rpm.crt

# Verify signature
cosign verify-blob --signature kmod-maccel-VERSION.rpm.sig --certificate kmod-maccel-VERSION.rpm.crt \
  --certificate-identity-regexp ".*" \
  --certificate-oidc-issuer-regexp ".*" \
  kmod-maccel-VERSION.rpm
```

### Additional Verification

Each release also includes:
- `checksums.txt` - SHA256 checksums for integrity verification
- `build-info.json` - Build metadata including source commit hashes
- `PACKAGE_VERIFICATION.md` - Comprehensive verification guide
- `sigstore-info.txt` - Detailed Sigstore verification instructions

## License

This project is licensed under the same terms as the upstream maccel project.