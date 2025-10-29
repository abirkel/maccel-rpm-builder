# Blue Build Integration Guide

This guide provides comprehensive instructions for integrating maccel RPM packages into Blue Build workflows and recipes.

## Overview

Blue Build is a framework for creating custom Fedora-based container images. This guide shows how to integrate maccel mouse acceleration into your Blue Build images using the RPM packages provided by this repository.

## Quick Integration

### Basic Recipe Integration

Add maccel packages to your Blue Build recipe:

```yaml
# recipe.yml
name: my-aurora-maccel
description: Aurora with maccel mouse acceleration
base-image: ghcr.io/ublue-os/aurora
image-version: 41

modules:
  - type: rpm-ostree
    install:
      # Replace USERNAME with actual GitHub username
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/kmod-maccel-1.0.0-1.fc41.x86_64.rpm
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/maccel-1.0.0-1.fc41.x86_64.rpm

  - type: systemd
    system:
      enabled:
        - maccel-setup.service
```

### Automatic Kernel Version Detection

For dynamic kernel version handling, use a GitHub Actions workflow:

```yaml
# .github/workflows/build.yml
name: Build Aurora with maccel

on:
  push:
    branches: [main]
  schedule:
    - cron: '0 6 * * *'  # Daily builds to catch kernel updates

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Get base image kernel version
        id: kernel
        run: |
          KERNEL_VERSION=$(skopeo inspect docker://ghcr.io/ublue-os/aurora:41 | \
            jq -r '.Labels["ostree.linux"]')
          echo "version=${KERNEL_VERSION}" >> $GITHUB_OUTPUT
          echo "Detected kernel version: ${KERNEL_VERSION}"
          
      - name: Check for existing maccel packages
        id: packages
        run: |
          # Check if packages exist for this kernel version
          RELEASE_TAG=$(gh api repos/USERNAME/maccel-rpm-builder/releases | \
            jq -r ".[] | select(.tag_name | contains(\"kernel-${{ steps.kernel.outputs.version }}\")) | .tag_name" | \
            head -1)
          
          if [ -n "$RELEASE_TAG" ]; then
            echo "found=true" >> $GITHUB_OUTPUT
            echo "release_tag=${RELEASE_TAG}" >> $GITHUB_OUTPUT
          else
            echo "found=false" >> $GITHUB_OUTPUT
          fi
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          
      - name: Trigger maccel build if needed
        if: steps.packages.outputs.found == 'false'
        run: |
          gh api repos/USERNAME/maccel-rpm-builder/dispatches \
            --method POST \
            --field event_type=build-for-kernel \
            --field client_payload="{\"kernel_version\":\"${{ steps.kernel.outputs.version }}\",\"fedora_version\":\"41\",\"trigger_repo\":\"${{ github.repository }}\"}"
          
          # Wait for build to complete
          echo "Waiting for maccel build to complete..."
          sleep 600  # Wait 10 minutes for build
        env:
          GITHUB_TOKEN: ${{ secrets.DISPATCH_TOKEN }}
          
      - name: Update recipe with package URLs
        run: |
          # Get the release tag (either existing or newly created)
          if [ "${{ steps.packages.outputs.found }}" == "true" ]; then
            RELEASE_TAG="${{ steps.packages.outputs.release_tag }}"
          else
            # Find the newly created release
            RELEASE_TAG=$(gh api repos/USERNAME/maccel-rpm-builder/releases | \
              jq -r ".[] | select(.tag_name | contains(\"kernel-${{ steps.kernel.outputs.version }}\")) | .tag_name" | \
              head -1)
          fi
          
          # Extract maccel version from release tag
          MACCEL_VERSION=$(echo $RELEASE_TAG | sed 's/.*maccel-//')
          
          # Update recipe.yml with correct URLs
          BASE_URL="https://github.com/USERNAME/maccel-rpm-builder/releases/download"
          KMOD_URL="${BASE_URL}/${RELEASE_TAG}/kmod-maccel-${MACCEL_VERSION}-1.fc41.x86_64.rpm"
          MACCEL_URL="${BASE_URL}/${RELEASE_TAG}/maccel-${MACCEL_VERSION}-1.fc41.x86_64.rpm"
          
          # Replace URLs in recipe
          sed -i "s|https://github.com/USERNAME/maccel-rpm-builder/releases/download/.*/kmod-maccel.*rpm|${KMOD_URL}|" recipe.yml
          sed -i "s|https://github.com/USERNAME/maccel-rpm-builder/releases/download/.*/maccel.*rpm|${MACCEL_URL}|" recipe.yml
          
          echo "Updated recipe with:"
          echo "  kmod-maccel: ${KMOD_URL}"
          echo "  maccel: ${MACCEL_URL}"
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          
      - name: Build Blue Build image
        uses: blue-build/github-action@v1
        with:
          recipe: recipe.yml
          cosign_private_key: ${{ secrets.SIGNING_SECRET }}
          registry_token: ${{ secrets.GITHUB_TOKEN }}
          pr_event_number: ${{ github.event.number }}
```

## Advanced Integration Patterns

### Multi-Architecture Support

```yaml
# recipe.yml with architecture detection
name: aurora-maccel-multi-arch
description: Aurora with maccel for multiple architectures
base-image: ghcr.io/ublue-os/aurora
image-version: 41

modules:
  - type: rpm-ostree
    install:
      # Use template variables for architecture
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/kmod-maccel-1.0.0-1.fc41.x86_64.rpm
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/maccel-1.0.0-1.fc41.x86_64.rpm

  # Add configuration files
  - type: files
    files:
      - source: config/maccel.conf
        dest: /etc/maccel/maccel.conf
      - source: config/99-maccel-permissions.rules
        dest: /etc/udev/rules.d/99-maccel-permissions.rules

  # Enable services
  - type: systemd
    system:
      enabled:
        - maccel-setup.service
      disabled:
        - libinput-gestures.service  # Disable conflicting services
```

### Version Pinning Strategy

```yaml
# recipe.yml with version pinning
name: aurora-maccel-stable
description: Aurora with pinned maccel version for stability
base-image: ghcr.io/ublue-os/aurora
image-version: 41

modules:
  - type: rpm-ostree
    install:
      # Pin to specific tested versions
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/kmod-maccel-1.0.0-1.fc41.x86_64.rpm
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/maccel-1.0.0-1.fc41.x86_64.rpm

  # Add version tracking
  - type: files
    files:
      - source: /dev/stdin
        dest: /etc/maccel-version
        content: |
          MACCEL_VERSION=1.0.0
          KERNEL_VERSION=6.11.5-300.fc41.x86_64
          BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
          RECIPE_COMMIT=${GITHUB_SHA:-unknown}
```

### Conditional Installation

```yaml
# recipe.yml with conditional maccel installation
name: aurora-maccel-optional
description: Aurora with optional maccel support
base-image: ghcr.io/ublue-os/aurora
image-version: 41

modules:
  # Only install maccel if ENABLE_MACCEL build arg is set
  - type: rpm-ostree
    install:
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/kmod-maccel-1.0.0-1.fc41.x86_64.rpm
      - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0/maccel-1.0.0-1.fc41.x86_64.rpm
    condition: ${ENABLE_MACCEL:-false}

  # Alternative: Use different recipes for different variants
  - type: files
    files:
      - source: scripts/setup-maccel.sh
        dest: /usr/local/bin/setup-maccel
        mode: '0755'
```

## Configuration Management

### Default Configuration Files

Create configuration files to include in your image:

```bash
# config/maccel.conf
# Default maccel configuration
[general]
acceleration = 1.5
sensitivity = 1.0
polling_rate = 1000

[profiles]
default = gaming
gaming = 2.0
office = 1.2
precision = 0.8
```

```bash
# config/99-maccel-permissions.rules
# Additional udev rules for maccel
SUBSYSTEM=="input", GROUP="maccel", MODE="0664"
KERNEL=="event*", SUBSYSTEM=="input", GROUP="maccel", MODE="0664"
```

### Systemd Service Configuration

```ini
# config/maccel-setup.service
[Unit]
Description=maccel Mouse Acceleration Setup
After=multi-user.target graphical-session.target
Wants=graphical-session.target

[Service]
Type=oneshot
ExecStartPre=/usr/bin/modprobe maccel
ExecStart=/usr/bin/udevadm control --reload-rules
ExecStart=/usr/bin/udevadm trigger
ExecStart=/usr/bin/systemctl --user enable maccel-user.service
RemainAfterExit=yes
User=root

[Install]
WantedBy=multi-user.target
```

### User Service Configuration

```ini
# config/maccel-user.service
[Unit]
Description=maccel User Configuration
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=/usr/bin/maccel load-profile default
ExecStart=/usr/bin/maccel enable
RemainAfterExit=yes
User=%i

[Install]
WantedBy=default.target
```

## Build Optimization

### Caching Strategy

```yaml
# .github/workflows/build-optimized.yml
name: Optimized Aurora maccel Build

on:
  push:
    branches: [main]
  schedule:
    - cron: '0 6 * * *'

jobs:
  check-updates:
    runs-on: ubuntu-latest
    outputs:
      kernel-changed: ${{ steps.check.outputs.kernel-changed }}
      maccel-changed: ${{ steps.check.outputs.maccel-changed }}
      should-build: ${{ steps.check.outputs.should-build }}
    steps:
      - uses: actions/checkout@v4
      
      - name: Check for updates
        id: check
        run: |
          # Get current kernel version from base image
          CURRENT_KERNEL=$(skopeo inspect docker://ghcr.io/ublue-os/aurora:41 | \
            jq -r '.Labels["ostree.linux"]')
          
          # Get last built kernel version
          LAST_KERNEL=$(cat .last-kernel-version 2>/dev/null || echo "")
          
          # Check maccel version
          CURRENT_MACCEL=$(gh api repos/Gnarus-G/maccel/releases/latest | jq -r '.tag_name')
          LAST_MACCEL=$(cat .last-maccel-version 2>/dev/null || echo "")
          
          # Determine if build is needed
          if [ "$CURRENT_KERNEL" != "$LAST_KERNEL" ]; then
            echo "kernel-changed=true" >> $GITHUB_OUTPUT
            echo "should-build=true" >> $GITHUB_OUTPUT
          else
            echo "kernel-changed=false" >> $GITHUB_OUTPUT
          fi
          
          if [ "$CURRENT_MACCEL" != "$LAST_MACCEL" ]; then
            echo "maccel-changed=true" >> $GITHUB_OUTPUT
            echo "should-build=true" >> $GITHUB_OUTPUT
          else
            echo "maccel-changed=false" >> $GITHUB_OUTPUT
          fi
          
          # Set should-build if either changed
          if [ "$CURRENT_KERNEL" != "$LAST_KERNEL" ] || [ "$CURRENT_MACCEL" != "$LAST_MACCEL" ]; then
            echo "should-build=true" >> $GITHUB_OUTPUT
          else
            echo "should-build=false" >> $GITHUB_OUTPUT
          fi
          
          echo "Current kernel: $CURRENT_KERNEL"
          echo "Last kernel: $LAST_KERNEL"
          echo "Current maccel: $CURRENT_MACCEL"
          echo "Last maccel: $LAST_MACCEL"
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  build:
    needs: check-updates
    if: needs.check-updates.outputs.should-build == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      # ... rest of build steps ...
      
      - name: Update version tracking
        run: |
          echo "${{ steps.kernel.outputs.version }}" > .last-kernel-version
          echo "${{ steps.maccel.outputs.version }}" > .last-maccel-version
          git add .last-*-version
          git commit -m "Update version tracking" || true
          git push || true
```

### Parallel Builds

```yaml
# .github/workflows/parallel-builds.yml
name: Parallel Aurora Builds

on:
  push:
    branches: [main]

jobs:
  prepare:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.matrix.outputs.matrix }}
    steps:
      - name: Generate build matrix
        id: matrix
        run: |
          # Generate matrix for different variants
          MATRIX=$(cat << 'EOF'
          {
            "include": [
              {
                "name": "aurora-maccel-gaming",
                "base": "ghcr.io/ublue-os/aurora",
                "config": "gaming",
                "maccel_profile": "gaming"
              },
              {
                "name": "aurora-maccel-office",
                "base": "ghcr.io/ublue-os/aurora",
                "config": "office", 
                "maccel_profile": "office"
              },
              {
                "name": "bazzite-maccel",
                "base": "ghcr.io/ublue-os/bazzite",
                "config": "gaming",
                "maccel_profile": "gaming"
              }
            ]
          }
          EOF
          )
          echo "matrix=${MATRIX}" >> $GITHUB_OUTPUT

  build:
    needs: prepare
    runs-on: ubuntu-latest
    strategy:
      matrix: ${{ fromJson(needs.prepare.outputs.matrix) }}
    steps:
      - uses: actions/checkout@v4
      
      - name: Generate recipe for ${{ matrix.name }}
        run: |
          # Generate variant-specific recipe
          cat > recipe-${{ matrix.config }}.yml << EOF
          name: ${{ matrix.name }}
          description: ${{ matrix.base }} with maccel (${{ matrix.config }} profile)
          base-image: ${{ matrix.base }}
          image-version: 41
          
          modules:
            - type: rpm-ostree
              install:
                - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-\${KERNEL_VERSION}-maccel-\${MACCEL_VERSION}/kmod-maccel-\${MACCEL_VERSION}-1.fc41.x86_64.rpm
                - https://github.com/USERNAME/maccel-rpm-builder/releases/download/kernel-\${KERNEL_VERSION}-maccel-\${MACCEL_VERSION}/maccel-\${MACCEL_VERSION}-1.fc41.x86_64.rpm
                
            - type: files
              files:
                - source: config/maccel-${{ matrix.config }}.conf
                  dest: /etc/maccel/maccel.conf
          EOF
          
      - name: Build ${{ matrix.name }}
        uses: blue-build/github-action@v1
        with:
          recipe: recipe-${{ matrix.config }}.yml
          cosign_private_key: ${{ secrets.SIGNING_SECRET }}
          registry_token: ${{ secrets.GITHUB_TOKEN }}
```

## Testing and Validation

### Integration Testing

```yaml
# .github/workflows/test-integration.yml
name: Test maccel Integration

on:
  pull_request:
    paths:
      - 'recipe.yml'
      - 'config/**'
      - '.github/workflows/**'

jobs:
  test-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Test recipe syntax
        run: |
          # Validate recipe YAML syntax
          python -c "import yaml; yaml.safe_load(open('recipe.yml'))"
          
      - name: Test package URLs
        run: |
          # Extract and test package URLs from recipe
          URLS=$(grep -o 'https://github.com/[^"]*\.rpm' recipe.yml)
          for url in $URLS; do
            echo "Testing URL: $url"
            curl -I "$url" | grep -q "200 OK" || {
              echo "ERROR: URL not accessible: $url"
              exit 1
            }
          done
          
      - name: Test build (dry run)
        uses: blue-build/github-action@v1
        with:
          recipe: recipe.yml
          dry_run: true

  test-functionality:
    runs-on: ubuntu-latest
    container:
      image: fedora:41
      options: --privileged
    steps:
      - name: Install test packages
        run: |
          # Download and install packages for testing
          KERNEL_VERSION="6.11.5-300.fc41.x86_64"
          MACCEL_VERSION="1.0.0"
          BASE_URL="https://github.com/USERNAME/maccel-rpm-builder/releases/download"
          RELEASE_TAG="kernel-${KERNEL_VERSION}-maccel-${MACCEL_VERSION}"
          
          dnf install -y wget
          wget "${BASE_URL}/${RELEASE_TAG}/kmod-maccel-${MACCEL_VERSION}-1.fc41.x86_64.rpm"
          wget "${BASE_URL}/${RELEASE_TAG}/maccel-${MACCEL_VERSION}-1.fc41.x86_64.rpm"
          
          dnf install -y ./kmod-maccel-*.rpm ./maccel-*.rpm
          
      - name: Test package installation
        run: |
          # Verify packages are installed
          rpm -qa | grep maccel
          
          # Test CLI tool
          maccel --version
          maccel --help
          
          # Check files are in place
          ls -la /etc/udev/rules.d/99-maccel.rules
          getent group maccel
```

### User Acceptance Testing

```bash
#!/bin/bash
# test-user-experience.sh

echo "=== maccel User Experience Test ==="

# Test 1: Package installation
echo "1. Testing package installation..."
rpm -qa | grep maccel && echo "✓ Packages installed" || echo "✗ Packages missing"

# Test 2: Kernel module
echo "2. Testing kernel module..."
lsmod | grep maccel && echo "✓ Module loaded" || echo "✗ Module not loaded"

# Test 3: CLI accessibility
echo "3. Testing CLI accessibility..."
which maccel && echo "✓ CLI accessible" || echo "✗ CLI not found"

# Test 4: User permissions
echo "4. Testing user permissions..."
groups $USER | grep maccel && echo "✓ User in maccel group" || echo "✗ User not in maccel group"

# Test 5: Device access
echo "5. Testing device access..."
maccel list-devices 2>/dev/null && echo "✓ Device access OK" || echo "⚠ Check device permissions"

# Test 6: Configuration
echo "6. Testing configuration..."
maccel config --show 2>/dev/null && echo "✓ Configuration accessible" || echo "⚠ Configuration issues"

echo "=== Test Complete ==="
```

## Troubleshooting Blue Build Integration

### Common Issues

#### Issue 1: Package URLs Not Found

**Problem**: Build fails with 404 errors for package URLs

**Solution**:
```yaml
# Add error handling to workflow
- name: Verify package availability
  run: |
    URLS=$(grep -o 'https://github.com/[^"]*\.rpm' recipe.yml)
    for url in $URLS; do
      if ! curl -I "$url" 2>/dev/null | grep -q "200 OK"; then
        echo "Package not found: $url"
        echo "Triggering build for missing packages..."
        
        # Extract kernel version from URL
        KERNEL_VERSION=$(echo "$url" | grep -o 'kernel-[^-]*-[^-]*-[^-]*\.[^-]*\.[^/]*' | sed 's/kernel-//')
        
        # Trigger build
        gh api repos/USERNAME/maccel-rpm-builder/dispatches \
          --method POST \
          --field event_type=build-for-kernel \
          --field client_payload="{\"kernel_version\":\"${KERNEL_VERSION}\",\"fedora_version\":\"41\",\"trigger_repo\":\"${{ github.repository }}\"}"
        
        # Wait for build
        sleep 600
      fi
    done
  env:
    GITHUB_TOKEN: ${{ secrets.DISPATCH_TOKEN }}
```

#### Issue 2: Kernel Version Mismatch

**Problem**: Packages built for wrong kernel version

**Solution**:
```bash
# Add kernel version validation
- name: Validate kernel versions
  run: |
    # Get base image kernel version
    BASE_KERNEL=$(skopeo inspect docker://ghcr.io/ublue-os/aurora:41 | \
      jq -r '.Labels["ostree.linux"]')
    
    # Get package kernel version from URL
    PACKAGE_KERNEL=$(grep -o 'kernel-[^-]*-[^-]*-[^-]*\.[^-]*\.[^/]*' recipe.yml | \
      head -1 | sed 's/kernel-//')
    
    if [ "$BASE_KERNEL" != "$PACKAGE_KERNEL" ]; then
      echo "Kernel version mismatch!"
      echo "Base image: $BASE_KERNEL"
      echo "Package: $PACKAGE_KERNEL"
      exit 1
    fi
```

#### Issue 3: Service Configuration Issues

**Problem**: maccel services don't start properly

**Solution**:
```yaml
# Add service validation
modules:
  - type: systemd
    system:
      enabled:
        - maccel-setup.service
      masked:
        - conflicting-service.service

  # Add service files
  - type: files
    files:
      - source: config/maccel-setup.service
        dest: /etc/systemd/system/maccel-setup.service
      - source: config/maccel-user.service
        dest: /etc/systemd/user/maccel-user.service

  # Add validation script
  - type: script
    snippets:
      - systemctl daemon-reload
      - systemctl enable maccel-setup.service
      - systemctl --user daemon-reload
```

### Debugging Tools

#### Build Log Analysis

```bash
# Download and analyze build logs
gh run download $RUN_ID --repo USERNAME/my-aurora-build

# Extract maccel-related errors
grep -i "maccel\|rpm\|error" */build.log

# Check for package installation issues
grep -A5 -B5 "rpm-ostree" */build.log
```

#### Container Testing

```bash
# Test recipe in local container
podman run -it --rm fedora:41 bash

# Inside container, test package installation
dnf install -y https://github.com/USERNAME/maccel-rpm-builder/releases/download/.../kmod-maccel-*.rpm
dnf install -y https://github.com/USERNAME/maccel-rpm-builder/releases/download/.../maccel-*.rpm

# Test functionality
modprobe maccel
maccel --version
```

## Best Practices

### Version Management

1. **Pin versions for production**: Use specific package versions in production recipes
2. **Test updates**: Always test new package versions before deploying
3. **Track changes**: Maintain changelog of package updates
4. **Rollback plan**: Keep previous working versions available

### Security Considerations

1. **Verify signatures**: Always verify package signatures in CI/CD
2. **Use HTTPS**: Only use HTTPS URLs for package downloads
3. **Audit dependencies**: Regularly audit package dependencies
4. **Monitor updates**: Set up notifications for security updates

### Performance Optimization

1. **Cache builds**: Use build caching to reduce build times
2. **Parallel builds**: Build multiple variants in parallel
3. **Conditional builds**: Only build when changes are detected
4. **Optimize layers**: Minimize container layers for faster pulls

### Documentation

1. **Document variants**: Clearly document different image variants
2. **Usage examples**: Provide clear usage examples
3. **Troubleshooting**: Maintain troubleshooting guides
4. **Update procedures**: Document update and rollback procedures

## Support and Resources

### Blue Build Resources
- [Blue Build Documentation](https://blue-build.org/)
- [Blue Build GitHub](https://github.com/blue-build/cli)
- [Blue Build Discord](https://discord.gg/blue-build)

### maccel Resources
- [maccel Repository](https://github.com/Gnarus-G/maccel)
- [maccel Documentation](https://github.com/Gnarus-G/maccel/blob/main/README.md)

### Universal Blue Resources
- [Universal Blue](https://universal-blue.org/)
- [Aurora Documentation](https://getaurora.dev/)
- [Bazzite Documentation](https://bazzite.gg/)

### Getting Help
- Create issues in the [maccel-rpm-builder repository](https://github.com/USERNAME/maccel-rpm-builder/issues)
- Join the [Blue Build Discord](https://discord.gg/blue-build) for community support
- Check the [Universal Blue forum](https://github.com/orgs/ublue-os/discussions) for general questions