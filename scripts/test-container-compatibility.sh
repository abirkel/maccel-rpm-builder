#!/bin/bash

# Test script to validate Fedora container compatibility with GitHub Actions
# This script tests the key components needed for the container-based build

set -euo pipefail

echo "🧪 Testing Fedora container compatibility for GitHub Actions"

# Test 1: Check if we're running in a container
echo "📋 Test 1: Container environment detection"
if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
    echo "✅ Running in container environment"
else
    echo "ℹ️  Not running in container (this is expected for local testing)"
fi

# Test 2: Check essential tools availability
echo "📋 Test 2: Essential tools availability"
REQUIRED_TOOLS=("git" "curl" "jq" "wget" "find" "which")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "✅ $tool is available"
    else
        echo "❌ $tool is missing"
        exit 1
    fi
done

# Test 3: Check GitHub CLI
echo "📋 Test 3: GitHub CLI availability"
if command -v gh >/dev/null 2>&1; then
    echo "✅ GitHub CLI is available"
    gh --version
else
    echo "❌ GitHub CLI is missing"
    exit 1
fi

# Test 4: Check RPM build tools (if available)
echo "📋 Test 4: RPM build tools availability"
RPM_TOOLS=("rpm-build" "rpmlint" "rpmdev-setuptree")
for tool in "${RPM_TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "✅ $tool is available"
    else
        echo "⚠️  $tool is not available (will be installed during build)"
    fi
done

# Test 5: Check build dependencies
echo "📋 Test 5: Build dependencies availability"
BUILD_DEPS=("gcc" "make" "rustc" "cargo")
for dep in "${BUILD_DEPS[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
        echo "✅ $dep is available"
    else
        echo "⚠️  $dep is not available (will be installed during build)"
    fi
done

# Test 6: Check file system permissions
echo "📋 Test 6: File system permissions"
TEST_DIR="/tmp/container-test-$$"
mkdir -p "$TEST_DIR"
echo "test content" > "$TEST_DIR/test-file"
chmod 644 "$TEST_DIR/test-file"

if [ -r "$TEST_DIR/test-file" ] && [ -w "$TEST_DIR/test-file" ]; then
    echo "✅ File system permissions work correctly"
    rm -rf "$TEST_DIR"
else
    echo "❌ File system permission issues detected"
    rm -rf "$TEST_DIR"
    exit 1
fi

# Test 7: Check environment variables
echo "📋 Test 7: Environment variables"
REQUIRED_VARS=("HOME" "USER" "SHELL")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -n "${!var:-}" ]; then
        echo "✅ $var is set to: ${!var}"
    else
        echo "⚠️  $var is not set"
    fi
done

# Test 8: Check Git configuration
echo "📋 Test 8: Git configuration"
if git config --global user.name >/dev/null 2>&1; then
    echo "✅ Git user.name is configured"
else
    echo "ℹ️  Git user.name not configured (will be set during workflow)"
fi

if git config --global user.email >/dev/null 2>&1; then
    echo "✅ Git user.email is configured"
else
    echo "ℹ️  Git user.email not configured (will be set during workflow)"
fi

# Test 9: Check network connectivity
echo "📋 Test 9: Network connectivity"
if curl -s --connect-timeout 5 https://api.github.com/zen >/dev/null; then
    echo "✅ Network connectivity to GitHub API works"
else
    echo "❌ Network connectivity issues detected"
    exit 1
fi

# Test 10: Check locale settings
echo "📋 Test 10: Locale settings"
if locale -a | grep -q "C.UTF-8\|en_US.UTF-8"; then
    echo "✅ UTF-8 locale is available"
else
    echo "⚠️  UTF-8 locale may not be available"
fi

echo ""
echo "🎉 Container compatibility test completed successfully!"
echo "The Fedora container environment should work properly with GitHub Actions."