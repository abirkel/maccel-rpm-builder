# Fedora Container Build Guide

## Overview

This document describes the Fedora container-based build system for the maccel-rpm-builder project, which provides native RPM packaging using authentic Fedora environments.

## Key Changes

### 1. Container Configuration

All jobs use Fedora containers for native RPM building:

```yaml
container:
  image: fedora:${{ github.event.client_payload.fedora_version || inputs.fedora_version || '41' }}
  options: --privileged --user root --tmpfs /tmp --tmpfs /var/tmp
  volumes:
    - /sys/fs/cgroup:/sys/fs/cgroup:rw
    - /lib/modules:/lib/modules:ro
    - /usr/src:/usr/src:ro
```

### 2. Container Setup Steps

Each job includes a container setup step that:
- Updates the Fedora package manager (`dnf`)
- Installs essential tools (git, curl, jq, wget, etc.)
- Installs GitHub CLI
- Configures Git for the container environment
- Sets up build tools (for build jobs)

### 3. Privileged Container Requirements

Kernel module builds require privileged containers with:
- `--privileged` flag for kernel module compilation
- `--user root` for proper permissions
- Volume mounts for kernel headers and system information
- Temporary filesystems for build artifacts

### 4. Environment Variables

Added container-specific environment variables:
- `HOME: /root`
- `USER: root`
- `SHELL: /bin/bash`
- `LANG: C.UTF-8`
- `LC_ALL: C.UTF-8`

### 5. File Permission Handling

Added explicit file permission fixes for:
- Package artifacts before upload
- Downloaded artifacts before processing
- Build directories and files

## Benefits

### Native Fedora Environment
- Uses the same package manager and tools as target systems
- Provides authentic Fedora build environment with native kernel-devel packages
- Ensures proper RPM packaging standards compliance

### Improved Reliability
- Consistent build environment across all runs
- Proper kernel module compilation with native tools
- Better dependency management with dnf

### Enhanced Security
- Isolated container environment
- Controlled package installation
- Reduced attack surface

## Container-Specific Considerations

### Volume Mounts
- `/sys/fs/cgroup`: Required for systemd and container management
- `/lib/modules`: Read-only access to kernel modules (if available)
- `/usr/src`: Read-only access to kernel sources (if available)

### Temporary Filesystems
- `/tmp` and `/var/tmp` mounted as tmpfs for better performance
- Automatic cleanup of temporary build files

### Network Access
- Full network access for downloading sources and dependencies
- GitHub API access for repository operations
- Package repository access for dnf operations

## Testing

### Container Compatibility Test
Run the container compatibility test to validate the environment:

```bash
./scripts/test-container-compatibility.sh
```

This test validates:
- Essential tool availability
- GitHub CLI functionality
- File system permissions
- Network connectivity
- Environment variable setup

### Workflow Testing
Test the complete workflow with:

```bash
# Trigger test dispatch
gh workflow run test-dispatch.yml --ref main
```

## Troubleshooting

### Common Issues

#### 1. Permission Denied Errors
**Symptom**: Files cannot be read/written in container
**Solution**: Ensure proper file permissions are set in container setup steps

#### 2. Missing Dependencies
**Symptom**: Build tools not found during compilation
**Solution**: Verify container setup step installs all required packages

#### 3. Git Configuration Issues
**Symptom**: Git operations fail with "unsafe repository" errors
**Solution**: Git safe directory configuration is set in container setup

#### 4. Network Connectivity
**Symptom**: Cannot download sources or access GitHub API
**Solution**: Check container network configuration and firewall settings

### Debug Commands

```bash
# Check container environment
docker run --rm -it fedora:41 /bin/bash

# Test package installation
dnf install -y git curl jq wget rpm-build

# Verify GitHub CLI installation
dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
dnf install -y gh
```

## Implementation Checklist

- [x] Configure all job configurations to use Fedora containers
- [x] Add container setup steps to all jobs
- [x] Configure privileged container options for kernel builds
- [x] Add proper volume mounts for kernel module compilation
- [x] Update environment variables for container compatibility
- [x] Add file permission handling for artifacts
- [x] Update test dispatch workflow for consistency
- [x] Create container compatibility test script
- [x] Validate YAML syntax for all workflow files
- [x] Document build process and troubleshooting

## Maintenance Tasks

1. **Monitor build performance** and optimize as needed
2. **Update Fedora versions** as new releases become available
3. **Validate package quality** with each Fedora release
4. **Keep documentation current** with build environment changes

## Compatibility Notes

### GitHub Actions Compatibility
- Fedora containers are fully supported by GitHub Actions
- Container services work with all standard GitHub Actions
- Artifact upload/download functions normally with proper permissions

### Build Tool Compatibility
- Native Fedora RPM tools provide optimal package quality
- Rust toolchain provides consistent compilation environment
- Kernel module compilation uses proper Fedora kernel-devel packages

### Integration Compatibility
- Repository dispatch mechanism unchanged
- Package naming and distribution unchanged
- Blue Build integration remains compatible