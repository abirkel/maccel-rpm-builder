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
- **Version detection**: Automatically detects latest maccel version from upstream
- **Build optimization**: Caches dependencies between builds

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

## Development

This repository follows the spec-driven development approach. See the [specification documents](.kiro/specs/rpm-packaging/) for detailed requirements and design.

## License

This project is licensed under the same terms as the upstream maccel project.