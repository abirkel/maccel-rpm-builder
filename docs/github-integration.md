# GitHub Integration Setup

This document describes the GitHub repository setup and integration configuration for the maccel-rpm-builder project.

## Repository Structure

```
.github/
├── workflows/
│   ├── build-rpm.yml          # Main RPM building workflow
│   └── test-dispatch.yml      # Repository dispatch testing
└── settings.yml               # Repository configuration

scripts/
├── setup-github-repo.sh       # Repository creation and setup
├── test-dispatch.sh           # Test repository dispatch trigger
└── validate-workflows.sh      # Workflow validation
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

### Test Workflow (`test-dispatch.yml`)

Simple workflow to test the repository dispatch mechanism by triggering the main build workflow.

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
gh api repos/USERNAME/maccel-rpm-builder/dispatches \
  --method POST \
  --field event_type=build-for-kernel \
  --field client_payload='{"kernel_version":"6.11.5-300.fc41.x86_64","fedora_version":"41","trigger_repo":"MyProject"}'
```

## Setup Instructions

### 1. Create GitHub Repository

Run the setup script:

```bash
./scripts/setup-github-repo.sh
```

This script will:
- Create the GitHub repository (public)
- Configure repository settings and topics
- Set up branch protection
- Push the initial commit

### 2. Test Repository Dispatch

Test the integration:

```bash
./scripts/test-dispatch.sh [kernel_version] [fedora_version] [trigger_repo] [force_rebuild]
```

Example:
```bash
./scripts/test-dispatch.sh "6.11.5-300.fc41.x86_64" "41" "test" "false"
```

### 3. Validate Workflows

Ensure workflows are properly configured:

```bash
./scripts/validate-workflows.sh
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

## Troubleshooting

### Common Issues

1. **Invalid kernel version format**: Ensure format matches `X.Y.Z-REL.fcN.ARCH`
2. **Authentication errors**: Ensure GitHub token has proper permissions
3. **Build failures**: Check workflow logs for detailed error messages
4. **Missing packages**: Verify release was created successfully

### Debugging

- Check workflow runs: `https://github.com/USERNAME/maccel-rpm-builder/actions`
- View releases: `https://github.com/USERNAME/maccel-rpm-builder/releases`
- Test dispatch: Use the test workflow or script

## Security Considerations

- Repository is public for package distribution
- Uses GitHub's built-in token authentication
- No sensitive secrets required for basic operation
- Package signing will be implemented in future tasks