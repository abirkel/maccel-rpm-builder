# maccel-rpm-builder

Automated RPM package builder for the [maccel mouse acceleration driver](https://github.com/Gnarus-G/maccel).

## Overview

This repository creates proper RPM packages for maccel on-demand, triggered by Blue Build workflows or manual requests. It produces two separate RPM packages following Fedora packaging standards:

- **kmod-maccel**: Kernel module package compiled for specific kernel versions
- **maccel**: Userspace CLI tools, configuration files, and udev rules

The system is designed for efficiency, automatically detecting existing packages and skipping unnecessary builds while providing stable download URLs for Blue Build consumption.

## Usage

### Repository Dispatch Trigger (Recommended)

The primary method for triggering builds is through GitHub's repository dispatch mechanism. This allows external repositories (like Blue Build workflows) to request package builds programmatically.

#### Using GitHub CLI

```bash
gh api repos/abirkel/maccel-rpm-builder/dispatches \
  --method POST \
  --field event_type=build-for-kernel \
  --field client_payload='{"kernel_version":"6.11.5-300.fc41.x86_64","fedora_version":"41","trigger_repo":"MyProject"}'
```

#### Using curl

```bash
curl -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token YOUR_TOKEN" \
  https://api.github.com/repos/abirkel/maccel-rpm-builder/dispatches \
  -d '{"event_type":"build-for-kernel","client_payload":{"kernel_version":"6.11.5-300.fc41.x86_64","fedora_version":"41","trigger_repo":"MyProject"}}'
```

#### From Blue Build Workflows

```yaml
- name: Trigger maccel RPM build
  run: |
    gh api repos/abirkel/maccel-rpm-builder/dispatches \
      --method POST \
      --field event_type=build-for-kernel \
      --field client_payload="{\"kernel_version\":\"${{ env.KERNEL_VERSION }}\",\"fedora_version\":\"${{ env.FEDORA_VERSION }}\",\"trigger_repo\":\"${{ github.repository }}\"}"
  env:
    GITHUB_TOKEN: ${{ secrets.DISPATCH_TOKEN }}
```

### Manual Trigger

For testing or one-off builds, use the GitHub Actions web interface or CLI:

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
https://github.com/abirkel/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/kmod-maccel-1.0.0-1.fc41.x86_64.rpm
https://github.com/abirkel/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/maccel-1.0.0-1.fc41.x86_64.rpm
```

## Efficiency Features

- **Smart caching**: Skips builds if packages already exist for the kernel version
- **Source change detection**: Compares maccel source commit hashes to avoid unnecessary rebuilds
- **Version detection**: Automatically detects latest maccel version from upstream
- **Build optimization**: Caches dependencies between builds
- **Existing package detection**: Returns URLs to existing packages when builds are skipped

## Integration

This builder is designed to integrate with Blue Build workflows. See the [MyAuroraBluebuild](https://github.com/abirkel/MyAuroraBluebuild) project for usage examples.

## Repository Dispatch Payload Format

### Required Fields

```json
{
  "event_type": "build-for-kernel",
  "client_payload": {
    "kernel_version": "6.11.5-300.fc41.x86_64",
    "fedora_version": "41",
    "trigger_repo": "MyAuroraBluebuild"
  }
}
```

### Optional Fields

```json
{
  "event_type": "build-for-kernel",
  "client_payload": {
    "kernel_version": "6.11.5-300.fc41.x86_64",
    "fedora_version": "41",
    "trigger_repo": "MyAuroraBluebuild",
    "force_rebuild": false,
    "maccel_version": "latest"
  }
}
```

### Field Descriptions

- **event_type**: Must be `"build-for-kernel"` (required)
- **kernel_version**: Full kernel version string including Fedora release (required)
  - Format: `{version}-{release}.fc{fedora_version}.{arch}`
  - Example: `"6.11.5-300.fc41.x86_64"`
- **fedora_version**: Fedora release number (required)
  - Example: `"41"`
- **trigger_repo**: Name of the repository triggering the build (required)
  - Used for logging and status reporting
  - Example: `"MyAuroraBluebuild"`
- **force_rebuild**: Force rebuild even if packages exist (optional, default: false)
  - Set to `true` to rebuild packages regardless of existing packages
  - Useful for testing or when build environment changes
- **maccel_version**: Specific maccel version to build (optional, default: "latest")
  - Use `"latest"` for automatic version detection
  - Specify exact version like `"1.0.0"` to build specific version

### Payload Examples

#### Basic Build Request
```json
{
  "event_type": "build-for-kernel",
  "client_payload": {
    "kernel_version": "6.11.5-300.fc41.x86_64",
    "fedora_version": "41",
    "trigger_repo": "MyAuroraBluebuild"
  }
}
```

#### Force Rebuild Request
```json
{
  "event_type": "build-for-kernel",
  "client_payload": {
    "kernel_version": "6.11.5-300.fc41.x86_64",
    "fedora_version": "41",
    "trigger_repo": "MyAuroraBluebuild",
    "force_rebuild": true
  }
}
```

#### Specific Version Request
```json
{
  "event_type": "build-for-kernel",
  "client_payload": {
    "kernel_version": "6.11.5-300.fc41.x86_64",
    "fedora_version": "41",
    "trigger_repo": "MyAuroraBluebuild",
    "maccel_version": "1.0.0"
  }
}
```

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
wget https://github.com/abirkel/maccel-rpm-builder/releases/download/RELEASE_TAG/kmod-maccel-VERSION.rpm
wget https://github.com/abirkel/maccel-rpm-builder/releases/download/RELEASE_TAG/kmod-maccel-VERSION.rpm.sig
wget https://github.com/abirkel/maccel-rpm-builder/releases/download/RELEASE_TAG/kmod-maccel-VERSION.rpm.crt

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

## Troubleshooting

### Common Issues

#### Build Failures

**Problem**: Build fails with "kernel-devel package not found"
```
Error: No package kernel-devel-6.11.5-300.fc41.x86_64 available
```

**Solution**: 
- Verify the kernel version exists in Fedora repositories
- Check if the kernel version format is correct
- Ensure the Fedora version matches the kernel version

**Problem**: Build fails with "maccel source not accessible"
```
Error: Failed to download maccel source from GitHub
```

**Solution**:
- Check if the maccel repository is accessible
- Verify GitHub API rate limits haven't been exceeded
- Ensure network connectivity from GitHub Actions runners

**Problem**: Rust compilation fails
```
Error: cargo build failed with exit code 101
```

**Solution**:
- Check if the maccel source is compatible with the Rust toolchain version
- Verify all Rust dependencies are available
- Check for compilation errors in the build logs

#### Repository Dispatch Issues

**Problem**: Repository dispatch doesn't trigger workflow
```
No workflow run created after sending dispatch event
```

**Solution**:
- Verify the repository dispatch token has correct permissions
- Check that the event_type matches exactly: `"build-for-kernel"`
- Ensure the target repository exists and is accessible
- Verify the workflow file is on the default branch

**Problem**: Invalid payload format error
```
Error: Invalid client_payload format
```

**Solution**:
- Ensure JSON payload is properly formatted
- Verify all required fields are present: `kernel_version`, `fedora_version`, `trigger_repo`
- Check that field values match expected formats

#### Package Detection Issues

**Problem**: Existing packages not detected, causing unnecessary rebuilds
```
Building packages that already exist for kernel version
```

**Solution**:
- Check GitHub API permissions for reading releases
- Verify release naming format matches expected pattern
- Ensure the detection script has access to repository metadata

**Problem**: Package download URLs not working
```
404 Not Found when downloading packages
```

**Solution**:
- Verify the release was created successfully
- Check that packages were uploaded to the release
- Ensure the download URL format matches the actual release structure

### Debugging Steps

#### 1. Check Workflow Status
```bash
# List recent workflow runs
gh run list --repo abirkel/maccel-rpm-builder

# Get details of a specific run
gh run view RUN_ID --repo abirkel/maccel-rpm-builder

# Download logs for debugging
gh run download RUN_ID --repo abirkel/maccel-rpm-builder
```

#### 2. Validate Kernel Version
```bash
# Check if kernel-devel package exists
podman run --rm fedora:41 dnf search kernel-devel-6.11.5-300.fc41.x86_64

# List available kernel versions
podman run --rm fedora:41 dnf list available 'kernel-devel*'
```

#### 3. Test Repository Dispatch
```bash
# Test dispatch with minimal payload
gh api repos/abirkel/maccel-rpm-builder/dispatches \
  --method POST \
  --field event_type=build-for-kernel \
  --field client_payload='{"kernel_version":"6.11.5-300.fc41.x86_64","fedora_version":"41","trigger_repo":"test"}'

# Check if workflow was triggered
gh run list --repo abirkel/maccel-rpm-builder --limit 1
```

#### 4. Verify Package Detection
```bash
# Clone the repository and test detection script
git clone https://github.com/abirkel/maccel-rpm-builder.git
cd maccel-rpm-builder

# Test existing package detection
./scripts/check-existing-packages.sh check 6.11.5-300.fc41.x86_64

# Get package information
./scripts/check-existing-packages.sh info 6.11.5-300.fc41.x86_64
```

### Getting Help

#### Log Analysis
When reporting issues, include:
- Complete workflow run logs
- Repository dispatch payload used
- Expected vs actual behavior
- Kernel version and Fedora version being built

#### Useful Commands for Debugging
```bash
# Check repository dispatch events (requires admin access)
gh api repos/abirkel/maccel-rpm-builder/events

# List all releases
gh release list --repo abirkel/maccel-rpm-builder

# Get release information
gh release view RELEASE_TAG --repo abirkel/maccel-rpm-builder

# Check repository permissions
gh api repos/abirkel/maccel-rpm-builder --jq '.permissions'
```

#### Contact and Support
- Create an issue in this repository for build-related problems
- Check the [maccel upstream repository](https://github.com/Gnarus-G/maccel) for maccel-specific issues
- Review [Blue Build documentation](https://blue-build.org/) for integration questions

## Documentation

### Comprehensive Guides

- **[Package Verification Guide](docs/PACKAGE_VERIFICATION.md)** - Complete package verification and security validation
- **[Installation Guide](docs/INSTALLATION_GUIDE.md)** - Detailed installation instructions for different use cases
- **[Blue Build Integration Guide](docs/BLUE_BUILD_INTEGRATION.md)** - Comprehensive Blue Build workflow integration
- **[GitHub Integration Guide](docs/github-integration.md)** - Repository dispatch and GitHub Actions setup

### Quick Reference

- **Package Verification**: See [PACKAGE_VERIFICATION.md](docs/PACKAGE_VERIFICATION.md) for Sigstore verification and security validation
- **Installation Methods**: See [INSTALLATION_GUIDE.md](docs/INSTALLATION_GUIDE.md) for standard Fedora, Blue Build, and container installation
- **Blue Build Recipes**: See [BLUE_BUILD_INTEGRATION.md](docs/BLUE_BUILD_INTEGRATION.md) for recipe examples and automation workflows
- **Troubleshooting**: Each guide includes comprehensive troubleshooting sections for common issues

## License

This project is licensed under the same terms as the upstream maccel project.