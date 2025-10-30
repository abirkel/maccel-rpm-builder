# maccel-rpm-builder

Automated RPM package builder for the [maccel mouse acceleration driver](https://github.com/Gnarus-G/maccel). This project creates proper Fedora RPM packages on-demand for integration with Blue Build workflows and custom Fedora images.

## What This Does

Builds two RPM packages following Fedora packaging standards:

- **kmod-maccel**: Kernel module compiled for specific kernel versions
- **maccel**: CLI tools, udev rules, and configuration files

Packages are built on-demand via GitHub Actions, cached efficiently, and published to GitHub Releases with Sigstore signatures for verification.

## Quick Start

### For Blue Build Users

Add to your Blue Build recipe:

```yaml
modules:
  - type: rpm-ostree
    repos:
      - https://github.com/YOUR_USERNAME/maccel-rpm-builder/releases/download/kernel-${KERNEL_VERSION}-maccel-${MACCEL_VERSION}
    install:
      - kmod-maccel
      - maccel
```

See [Blue Build Integration Guide](docs/BLUE_BUILD_INTEGRATION.md) for complete examples.

### Trigger a Build

Using GitHub CLI:

```bash
gh api repos/YOUR_USERNAME/maccel-rpm-builder/dispatches \
  --method POST \
  --field event_type=build-for-kernel \
  --field client_payload='{"kernel_version":"6.11.5-300.fc42.x86_64","fedora_version":"42","trigger_repo":"MyProject"}'
```

Or manually via GitHub Actions web interface: Actions → Build RPM Packages → Run workflow

## How It Works

1. **Triggered by repository dispatch** from Blue Build workflows or manual requests
2. **Checks for existing packages** - skips build if already available
3. **Detects maccel version** from upstream releases
4. **Builds in Fedora containers** using proper RPM tooling
5. **Signs with Sigstore** for transparency and verification
6. **Publishes to GitHub Releases** with stable download URLs

### Efficiency Features

- **Smart caching**: Skips builds when packages exist for the kernel version
- **Source tracking**: Compares commit hashes to detect upstream changes
- **Cargo caching**: Speeds up Rust compilation on repeated builds
- **Fail-fast validation**: Catches errors early before expensive builds

## Package Downloads

Packages follow this URL pattern:

```
https://github.com/YOUR_USERNAME/maccel-rpm-builder/releases/download/kernel-{KERNEL_VERSION}-maccel-{MACCEL_VERSION}/{PACKAGE_NAME}.rpm
```

Example:

```
https://github.com/YOUR_USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc42.x86_64-maccel-1.0.0/kmod-maccel-1.0.0-1.fc42.x86_64.rpm
```

Each release includes:
- RPM packages (kmod-maccel and maccel)
- Sigstore signatures (.sig and .crt files)
- SHA256 checksums (checksums.txt)
- Build metadata (build-info.json)
- Verification instructions

## Repository Dispatch API

### Required Payload

```json
{
  "event_type": "build-for-kernel",
  "client_payload": {
    "kernel_version": "6.11.5-300.fc42.x86_64",
    "fedora_version": "42",
    "trigger_repo": "MyProject"
  }
}
```

### Optional Parameters

- `force_rebuild`: Set to `true` to rebuild even if packages exist
- `maccel_version`: Specify exact version (default: auto-detect latest)

### Field Formats

- **kernel_version**: `{version}-{release}.fc{N}.{arch}` (e.g., `6.11.5-300.fc42.x86_64`)
- **fedora_version**: Numeric string matching kernel version (e.g., `"42"`)
- **trigger_repo**: Repository name for logging (e.g., `"MyAuroraBluebuild"`)

## Package Verification

All packages are signed with Sigstore for transparency:

```bash
# Install cosign
curl -sLO https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
chmod +x cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign

# Verify package
cosign verify-blob \
  --signature kmod-maccel-1.0.0-1.fc42.x86_64.rpm.sig \
  --certificate kmod-maccel-1.0.0-1.fc42.x86_64.rpm.crt \
  --certificate-identity-regexp ".*" \
  --certificate-oidc-issuer-regexp ".*" \
  kmod-maccel-1.0.0-1.fc42.x86_64.rpm
```

See [Package Verification Guide](docs/PACKAGE_VERIFICATION.md) for complete verification instructions.

## Documentation

- **[Blue Build Integration](docs/BLUE_BUILD_INTEGRATION.md)** - Complete integration guide with recipe examples
- **[Installation Guide](docs/INSTALLATION_GUIDE.md)** - Installation methods for different use cases
- **[Package Verification](docs/PACKAGE_VERIFICATION.md)** - Security validation and signature verification
- **[GitHub Integration](docs/github-integration.md)** - Repository dispatch and automation setup

## Troubleshooting

### Build fails with "kernel-devel not found"

The exact kernel-devel version must be available in Fedora repositories. Check available versions:

```bash
podman run --rm fedora:42 dnf list available 'kernel-devel*'
```

### Repository dispatch doesn't trigger workflow

Verify:
- Token has `repo` scope permissions
- Event type is exactly `"build-for-kernel"`
- Payload JSON is valid
- Workflow file exists on default branch

### Packages not detected, causing unnecessary rebuilds

Check:
- GitHub token has read access to releases
- Release naming matches pattern: `kernel-{VERSION}-maccel-{VERSION}`
- Network connectivity to GitHub API

### Debug workflow runs

```bash
# List recent runs
gh run list --repo YOUR_USERNAME/maccel-rpm-builder

# View specific run
gh run view RUN_ID --repo YOUR_USERNAME/maccel-rpm-builder

# Download logs
gh run download RUN_ID --repo YOUR_USERNAME/maccel-rpm-builder
```

## Development

### Project Structure

```
maccel-rpm-builder/
├── .github/workflows/
│   └── build-rpm.yml          # Main build workflow
├── scripts/
│   ├── build-packages.sh      # RPM package building
│   ├── setup-build-environment.sh
│   ├── detect-maccel-version.sh
│   ├── check-existing-packages.sh
│   ├── sign-packages.sh       # Sigstore signing
│   └── error-handling.sh      # Shared utilities
├── kmod-maccel.spec           # Kernel module spec
├── maccel.spec                # Userspace tools spec
└── docs/                      # Comprehensive guides
```

### Testing

```bash
# Run validation tests
./scripts/test-runner.sh unit

# Test package detection
./scripts/check-existing-packages.sh check 6.11.5-300.fc42.x86_64

# Validate spec files
rpmlint kmod-maccel.spec maccel.spec

# Check shell scripts
shellcheck scripts/*.sh
```

### Contributing

This project follows Fedora packaging guidelines and uses:
- Shellcheck for script validation
- rpmlint for spec file validation
- Conventional commits for clear history

## Architecture

Built for efficiency and reliability:

- **Fedora containers**: Clean, reproducible build environment
- **Fail-fast validation**: Input validation before expensive operations
- **Proper error handling**: Structured logging and error reporting
- **No flawed fallbacks**: Exact version matching, no "close enough" logic
- **Sigstore signing**: Transparent, keyless package signing
- **GitHub OIDC**: Secure authentication without stored secrets

## License

This project is licensed under the same terms as the upstream [maccel project](https://github.com/Gnarus-G/maccel).

## Credits

- **maccel**: [Gnarus-G/maccel](https://github.com/Gnarus-G/maccel) - The upstream mouse acceleration driver
- **Blue Build**: [blue-build.org](https://blue-build.org/) - Custom Fedora image framework
- **Sigstore**: [sigstore.dev](https://www.sigstore.dev/) - Transparent package signing infrastructure
