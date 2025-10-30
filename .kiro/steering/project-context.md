---
inclusion: always
---

# maccel-rpm-builder Project Context

## Project Overview

This project creates proper RPM packages for the maccel mouse acceleration driver. It's part of a larger migration from a custom Containerfile approach (Vespera) to a standard Blue Build framework.

## Development Environment

**Tools Available**: 
- `gh` CLI tool for GitHub operations
- Standard Linux development tools
- RPM packaging tools (rpm-build, rpmlint)

## Architecture Context

### Original Vespera Approach
- Custom multi-stage Containerfile with kernel module compilation
- Direct file copying for maccel integration
- Complex build logic in GitHub Actions
- Worked but was over-engineered for the actual needs

### New RPM Builder Approach
- Proper Fedora RPM packaging following community standards
- Two separate packages: `kmod-maccel` (kernel module) and `maccel` (CLI tools)
- On-demand building triggered by Blue Build workflows
- Efficient caching to avoid unnecessary rebuilds

## Key Design Decisions

### Package Naming
- **kmod-maccel**: Kernel module package following Fedora `kmod-*` convention
- **maccel**: Userspace CLI tools package
- Standard RPM naming: `{name}-{version}-{release}.fc{N}.{arch}.rpm`

### Version Detection Strategy
1. **Git release tags** (preferred): Extract from maccel repository releases
2. **Cargo.toml version** (fallback): Parse from main branch
3. **Git commit hash** (final fallback): Use with 0.0.0 prefix

### Build Efficiency
- Check for existing packages before building
- Skip builds if kernel version and maccel source haven't changed
- Cache build dependencies between runs
- Use GitHub Releases for package distribution

## Integration with MyAuroraBluebuild

This RPM builder is triggered by the MyAuroraBluebuild project via repository dispatch.

### API Contract

This section defines the stable interface between maccel-rpm-builder and MyAuroraBluebuild. Changes to these contracts require coordinated updates in both projects.

#### Repository Dispatch Payload

**Event Type**: `build-for-kernel`

**Payload Schema**:
```json
{
  "event_type": "build-for-kernel",
  "client_payload": {
    "kernel_version": "6.11.5-300.fc41.x86_64",  // Required: Full kernel version string
    "fedora_version": "42",                       // Optional: Defaults to 42
    "trigger_repo": "MyAuroraBluebuild",         // Optional: For logging/tracking
    "force_rebuild": false                        // Optional: Skip cache, force rebuild
  }
}
```

**Field Specifications**:
- `kernel_version` (required, string): Format `X.Y.Z-REL.fcN.ARCH` where ARCH is `x86_64` or `aarch64`
- `fedora_version` (optional, string): Numeric version 35-50, defaults to "42"
- `trigger_repo` (optional, string): Repository name for audit trail
- `force_rebuild` (optional, boolean): When true, bypasses all caching

#### Release Tag Format

**Pattern**: `kernel-{KERNEL_VERSION}-maccel-{MACCEL_VERSION}`

**Example**: `kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0`

**Components**:
- `kernel-` prefix (literal)
- Full kernel version string (matches input)
- `-maccel-` separator (literal)
- Maccel semantic version (X.Y.Z format)

#### Package Naming Convention

**Pattern**: `{name}-{version}-{release}.fc{N}.{arch}.rpm`

**Examples**:
- `kmod-maccel-1.0.0-1.fc42.x86_64.rpm`
- `maccel-1.0.0-1.fc42.x86_64.rpm`

**Components**:
- `name`: Either `kmod-maccel` or `maccel`
- `version`: Maccel version (X.Y.Z)
- `release`: RPM release number (typically "1")
- `fcN`: Fedora version (e.g., fc42)
- `arch`: Architecture (x86_64 or aarch64)

#### Package Download URLs

**Base URL**: `https://github.com/{owner}/maccel-rpm-builder/releases/download/{release_tag}/{package_name}`

**Example**:
```
https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/kmod-maccel-1.0.0-1.fc41.x86_64.rpm
```

**URL Construction**:
1. Base: `https://github.com/{owner}/maccel-rpm-builder/releases/download/`
2. Release tag: `kernel-{KERNEL_VERSION}-maccel-{MACCEL_VERSION}/`
3. Package name: `{name}-{version}-{release}.fc{N}.{arch}.rpm`

## Maccel Source Analysis

Based on examination of https://github.com/Gnarus-G/maccel:

### Build Process
- **Kernel module**: Uses `driver/Makefile` with kernel build system
- **CLI tool**: Rust workspace with `cargo build --bin maccel --release`
- **Installation**: Uses `install.sh` script with DKMS (not relevant for our RPM approach)

### Required Configuration
- **Udev rules**: Device access permissions for maccel group
- **Module loading**: Auto-load kernel module at boot
- **Group creation**: `maccel` group for non-root access

## Best Practices

### RPM Packaging
- Follow Fedora packaging guidelines strictly
- Use `rpmlint` to validate spec files
- Include proper dependencies and metadata
- Handle pre/post install scripts correctly

### GitHub Integration
- Use repository dispatch for cross-repo coordination
- Implement proper error handling and status reporting
- Provide stable download URLs for package consumption
- Tag releases with descriptive names

### Testing Strategy
- Validate RPM packages in clean environments
- Test kernel module loading and CLI functionality
- Verify integration with Blue Build workflows
- Test caching and efficiency mechanisms

## Common Pitfalls to Avoid

1. **Don't use DKMS approach** - We're building for specific kernel versions
2. **Don't skip version detection** - Always use proper upstream versions
3. **Don't ignore caching** - Efficiency is crucial for good user experience
4. **Don't over-complicate** - Keep build scripts simple and maintainable

## Related Projects

- **MyAuroraBluebuild**: Consumes the RPM packages produced by this builder
- **Original Vespera**: Reference implementation showing what functionality to preserve
- **Upstream maccel**: Source of truth for build process and configuration requirements

## ⚠️ INTERDEPENDENCY ALERT ⚠️

**CRITICAL**: This project has tight integration with MyAuroraBluebuild. When making changes to this project, always consider if they affect the other project and notify the user to review/update accordingly.

### Changes That Require MyAuroraBluebuild Updates:

1. **Package naming changes** (kmod-maccel, maccel) → Update download URLs and package references
2. **Release naming format changes** → Update package detection logic
3. **Repository dispatch payload changes** → Update trigger mechanism
4. **Download URL structure changes** → Update package installation scripts
5. **RPM package content changes** (udev rules, group creation) → Update verification logic
6. **Build failure handling changes** → Update error handling and fallback mechanisms
7. **GitHub API changes** → Update authentication and API calls

### Changes That Require User Notification:

- **Version detection method changes** → May affect package versioning consistency
- **Caching strategy changes** → May affect build coordination timing
- **Error reporting changes** → May affect debugging and troubleshooting
- **Security/signing changes** → May affect package verification

**ACTION REQUIRED**: When implementing changes that fall into the above categories, explicitly notify the user to review and potentially update the MyAuroraBluebuild project to maintain compatibility.