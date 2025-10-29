# GitHub Integration Setup

This document describes the GitHub repository setup and integration configuration for the maccel-rpm-builder project.

## Repository Structure

```
.github/
└── workflows/
    └── build-rpm.yml          # Main RPM building workflow

scripts/
├── test-runner.sh             # Unified test runner (includes dispatch testing)
├── build-packages.sh          # Package building logic
├── setup-build-environment.sh # Build environment setup
├── detect-maccel-version.sh   # Version detection
├── check-existing-packages.sh # Package existence checking
├── sign-packages.sh           # Package signing
├── build-notifications.sh     # Build status notifications
└── error-handling.sh          # Error handling library
```

## GitHub Actions Workflows

### Main Build Workflow (`build-rpm.yml`)

**Triggers:**
- `repository_dispatch` with event type `build-for-kernel`
- Manual `workflow_dispatch` for testing

**Jobs:**
1. **validate-and-check**: Validates input and checks for existing packages
2. **build-packages**: Builds RPM packages (matrix strategy for both packages)
3. **create-release**: Creates GitHub release with packages
4. **report-existing**: Reports when packages already exist

**Key Features:**
- Kernel version format validation
- Automatic maccel version detection
- Existing package detection to avoid unnecessary builds
- Build matrix for both `kmod-maccel` and `maccel` packages
- Automatic GitHub release creation

### Testing

Repository dispatch testing is handled by the unified test runner:

```bash
./scripts/test-runner.sh integration
```

This provides comprehensive end-to-end testing of the repository dispatch mechanism.

## Repository Dispatch Integration

### Payload Format

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

### Triggering from External Repositories

```bash
# Using GitHub CLI
gh api repos/USERNAME/maccel-rpm-builder/dispatches \
  --method POST \
  --field event_type=build-for-kernel \
  --field client_payload='{"kernel_version":"6.11.5-300.fc41.x86_64","fedora_version":"41","trigger_repo":"MyProject","force_rebuild":false}'

# Using curl
curl -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/USERNAME/maccel-rpm-builder/dispatches \
  -d '{"event_type":"build-for-kernel","client_payload":{"kernel_version":"6.11.5-300.fc41.x86_64","fedora_version":"41","trigger_repo":"MyProject","force_rebuild":false}}'
```

## Setup Instructions

### 1. Create GitHub Repository

Create the repository manually through GitHub's web interface or using the GitHub CLI:

```bash
gh repo create maccel-rpm-builder --public --description "Automated RPM package builder for maccel mouse acceleration driver"
```

Configure repository settings:
- Enable Issues
- Disable Projects and Wiki
- Set topics: `rpm`, `packaging`, `maccel`, `mouse-acceleration`, `fedora`, `blue-build`, `automation`

### 2. Test Repository Dispatch

Test the integration using the unified test runner:

```bash
# Quick integration test
./scripts/test-runner.sh integration

# Full test suite (includes cross-version testing)
./scripts/test-runner.sh all
```

### 3. Validate Environment

Ensure your local development environment is properly set up:

```bash
# Check prerequisites and validate workflows
./scripts/test-runner.sh unit
```

## Release Management

### Release Naming Convention

Releases follow the format: `kernel-{KERNEL_VERSION}-maccel-{MACCEL_VERSION}`

Example: `kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0`

### Package Naming Convention

RPM packages follow Fedora standards:
- `kmod-maccel-{VERSION}-{RELEASE}.fc{N}.{ARCH}.rpm`
- `maccel-{VERSION}-{RELEASE}.fc{N}.{ARCH}.rpm`

### Download URLs

Packages are available at predictable URLs:
```
https://github.com/USERNAME/maccel-rpm-builder/releases/download/{RELEASE_TAG}/{PACKAGE_NAME}
```

## Version Detection

The system automatically detects maccel versions using multiple methods:

1. **Git release tags** (preferred): Latest release from upstream
2. **Cargo.toml version** (fallback): Version from main branch
3. **Git commit hash** (final fallback): `0.0.0+{short_hash}` format

## Efficiency Features

### Existing Package Detection

Before building, the workflow checks if packages already exist for the requested kernel version and maccel version combination. If found, it skips the build and returns existing package URLs.

### Force Rebuild

Set `force_rebuild: true` in the payload to force rebuilding even when packages exist.

### Build Caching

The workflow is designed to cache build dependencies between runs to improve performance.

## Integration with Blue Build

This repository is designed to integrate seamlessly with Blue Build workflows:

1. Blue Build queries Aurora base image for kernel version
2. Blue Build sends repository dispatch to this builder
3. Builder creates or returns existing RPM packages
4. Blue Build downloads and installs packages in container image

## Testing and Validation

### Local Testing

```bash
# Prerequisites check (required tools, authentication, etc.)
./scripts/test-runner.sh unit

# End-to-end integration test (triggers actual workflow)
./scripts/test-runner.sh integration

# Performance testing (caching efficiency)
./scripts/test-runner.sh performance

# Error handling validation
./scripts/test-runner.sh error

# Cross-version compatibility (multiple Fedora versions)
./scripts/test-runner.sh cross-version
```

### Test Requirements

- **GitHub CLI** (`gh`) - installed and authenticated
- **rpmlint** - for RPM spec validation
- **curl**, **jq**, **git** - for API calls and data processing

Install missing tools:
```bash
# Fedora/RHEL
sudo dnf install gh rpmlint curl jq git

# Ubuntu/Debian  
sudo apt install gh rpmlint curl jq git

# macOS
brew install gh rpmlint curl jq git
```

## Troubleshooting

### Common Issues

1. **Invalid kernel version format**: Ensure format matches `X.Y.Z-REL.fcN.ARCH`
2. **Authentication errors**: Run `gh auth login` to authenticate
3. **Build failures**: Check workflow logs for detailed error messages
4. **Missing packages**: Verify release was created successfully
5. **Test failures**: Ensure all required tools are installed

### Debugging

- Check workflow runs: `https://github.com/USERNAME/maccel-rpm-builder/actions`
- View releases: `https://github.com/USERNAME/maccel-rpm-builder/releases`
- Test dispatch: `./scripts/test-runner.sh integration --verbose`
- Validate environment: `./scripts/test-runner.sh unit`

## Security Considerations

- Repository is public for package distribution
- Uses GitHub's built-in token authentication
- No sensitive secrets required for basic operation
- Package signing will be implemented in future tasks