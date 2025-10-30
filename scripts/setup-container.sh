#!/bin/bash

# Container Setup Script for maccel RPM Builder
# This script sets up Fedora containers with required tools for building RPM packages
# Can be used for minimal setup (validation/release) or full setup (building)

set -euo pipefail

# Script parameters
SETUP_TYPE="${1:-minimal}"  # minimal or full

echo "Setting up Fedora container environment (${SETUP_TYPE} setup)..."

# Optimize dnf for faster package installation
echo 'fastestmirror=1' >> /etc/dnf/dnf.conf
echo 'max_parallel_downloads=10' >> /etc/dnf/dnf.conf
echo 'deltarpm=0' >> /etc/dnf/dnf.conf

# Update package manager
dnf update -y

# Install base packages (needed for all jobs)
echo "Installing base packages..."
dnf install -y git curl jq wget findutils which

# Install GitHub CLI
echo "Installing GitHub CLI..."
curl -fsSL https://cli.github.com/packages/rpm/gh-cli.repo | tee /etc/yum.repos.d/gh-cli.repo
dnf install -y gh

# Set up Git configuration for container
REPO_PATH="/__w/$(basename ${GITHUB_REPOSITORY:-maccel-rpm-builder})/$(basename ${GITHUB_REPOSITORY:-maccel-rpm-builder})"
git config --global --add safe.directory "$REPO_PATH" 2>/dev/null || true

# Full setup includes build tools
if [[ "$SETUP_TYPE" == "full" ]]; then
    echo "Installing build tools..."
    dnf install -y \
        rpm-build \
        rpmdevtools \
        rpmlint \
        make \
        gcc \
        gcc-c++ \
        rust \
        cargo \
        pkg-config \
        elfutils-libelf-devel \
        udev \
        kmod
    
    # Install Sigstore cosign for package signing
    echo "Installing Sigstore cosign..."
    curl -sLO https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
    chmod +x cosign-linux-amd64
    mv cosign-linux-amd64 /usr/local/bin/cosign
    
    # Set up RPM build environment
    echo "Setting up RPM build tree..."
    rpmdev-setuptree 2>/dev/null || true
    
    # Verify Rust toolchain
    echo "Verifying Rust toolchain..."
    rustc --version
    cargo --version
fi

echo "Container setup complete!"
