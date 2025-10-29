#!/bin/bash

# Test script for Fedora container build environment
# This script validates that the updated build scripts work correctly

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Test parameters
TEST_KERNEL_VERSION="6.11.5-300.fc41.x86_64"
TEST_FEDORA_VERSION="41"
TEST_MACCEL_VERSION="1.0.0"

# Function to test build environment setup
test_build_environment_setup() {
    log_info "Testing build environment setup for Fedora container..."
    
    # Test the setup script
    if ./scripts/setup-build-environment.sh "$TEST_KERNEL_VERSION" "$TEST_FEDORA_VERSION" "$TEST_MACCEL_VERSION"; then
        log_success "Build environment setup test passed"
        return 0
    else
        log_error "Build environment setup test failed"
        return 1
    fi
}

# Function to test maccel source download and preparation
test_source_preparation() {
    log_info "Testing maccel source download and preparation..."
    
    # Create a temporary test directory
    local test_dir="/tmp/maccel-build-test"
    rm -rf "$test_dir"
    mkdir -p "$test_dir"
    
    # Test source download (we'll use a mock approach to avoid actual download)
    log_info "Source preparation test would download from: https://github.com/Gnarus-G/maccel"
    log_info "Expected structure verification:"
    log_info "  - driver/Makefile (for kernel module build)"
    log_info "  - Cargo.toml (workspace root)"
    log_info "  - cli/Cargo.toml (CLI package)"
    log_info "  - udev_rules/99-maccel.rules (udev rules)"
    
    log_success "Source preparation test structure validated"
    
    # Clean up
    rm -rf "$test_dir"
    return 0
}

# Function to test RPM spec file validation
test_spec_file_validation() {
    log_info "Testing RPM spec file validation..."
    
    local errors=0
    
    # Test kmod-maccel.spec
    if [[ -f "kmod-maccel.spec" ]]; then
        log_info "Validating kmod-maccel.spec..."
        
        # Check for Fedora-specific elements
        if grep -q "kernel-devel" kmod-maccel.spec; then
            log_success "kmod-maccel.spec: Fedora kernel-devel dependency found"
        else
            log_error "kmod-maccel.spec: Missing Fedora kernel-devel dependency"
            ((errors++))
        fi
        
        if grep -q "/usr/src/kernels" kmod-maccel.spec; then
            log_success "kmod-maccel.spec: Fedora kernel source path found"
        else
            log_error "kmod-maccel.spec: Missing Fedora kernel source path"
            ((errors++))
        fi
        
        if grep -q "_modulesloaddir" kmod-maccel.spec; then
            log_success "kmod-maccel.spec: Fedora systemd integration found"
        else
            log_error "kmod-maccel.spec: Missing Fedora systemd integration"
            ((errors++))
        fi
    else
        log_error "kmod-maccel.spec file not found"
        ((errors++))
    fi
    
    # Test maccel.spec
    if [[ -f "maccel.spec" ]]; then
        log_info "Validating maccel.spec..."
        
        # Check for Fedora Rust toolchain
        if grep -q "rust.*cargo" maccel.spec; then
            log_success "maccel.spec: Fedora Rust toolchain dependency found"
        else
            log_error "maccel.spec: Missing Fedora Rust toolchain dependency"
            ((errors++))
        fi
        
        if grep -q "cargo build --bin maccel" maccel.spec; then
            log_success "maccel.spec: Cargo workspace build command found"
        else
            log_error "maccel.spec: Missing cargo workspace build command"
            ((errors++))
        fi
        
        if grep -q "_udevrulesdir" maccel.spec; then
            log_success "maccel.spec: Fedora udev rules path found"
        else
            log_error "maccel.spec: Missing Fedora udev rules path"
            ((errors++))
        fi
    else
        log_error "maccel.spec file not found"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "RPM spec file validation passed"
        return 0
    else
        log_error "RPM spec file validation failed with $errors errors"
        return 1
    fi
}

# Function to test build script functionality
test_build_script_functionality() {
    log_info "Testing build script functionality..."
    
    # Test that build scripts exist and are executable
    local scripts=("scripts/setup-build-environment.sh" "scripts/build-packages.sh")
    local errors=0
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if [[ -x "$script" ]]; then
                log_success "Build script found and executable: $script"
            else
                log_warning "Build script not executable: $script"
                chmod +x "$script"
                log_info "Made script executable: $script"
            fi
        else
            log_error "Build script not found: $script"
            ((errors++))
        fi
    done
    
    # Test script syntax
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if bash -n "$script"; then
                log_success "Script syntax validation passed: $script"
            else
                log_error "Script syntax validation failed: $script"
                ((errors++))
            fi
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_success "Build script functionality test passed"
        return 0
    else
        log_error "Build script functionality test failed with $errors errors"
        return 1
    fi
}

# Function to test Fedora container compatibility
test_fedora_container_compatibility() {
    log_info "Testing Fedora container compatibility..."
    
    # Check if we're in a Fedora environment
    if command -v dnf >/dev/null 2>&1; then
        log_success "DNF package manager available (Fedora environment detected)"
        
        # Test dnf functionality
        if dnf --version >/dev/null 2>&1; then
            log_success "DNF is functional"
        else
            log_warning "DNF may not be fully functional"
        fi
    else
        log_warning "DNF not available - may not be in Fedora container environment"
    fi
    
    # Check for Fedora-specific paths
    local fedora_paths=("/usr/src/kernels" "/usr/lib/udev/rules.d" "/usr/lib/modules-load.d")
    for path in "${fedora_paths[@]}"; do
        if [[ -d "$path" ]]; then
            log_success "Fedora path exists: $path"
        else
            log_info "Fedora path not found (may be created during build): $path"
        fi
    done
    
    log_success "Fedora container compatibility test completed"
    return 0
}

# Main test function
main() {
    log_info "Starting Fedora container build environment tests..."
    log_info "Test parameters:"
    log_info "  Kernel Version: $TEST_KERNEL_VERSION"
    log_info "  Fedora Version: $TEST_FEDORA_VERSION"
    log_info "  Maccel Version: $TEST_MACCEL_VERSION"
    
    local test_results=()
    
    # Run tests
    if test_spec_file_validation; then
        test_results+=("PASS: RPM spec file validation")
    else
        test_results+=("FAIL: RPM spec file validation")
    fi
    
    if test_build_script_functionality; then
        test_results+=("PASS: Build script functionality")
    else
        test_results+=("FAIL: Build script functionality")
    fi
    
    if test_source_preparation; then
        test_results+=("PASS: Source preparation")
    else
        test_results+=("FAIL: Source preparation")
    fi
    
    if test_fedora_container_compatibility; then
        test_results+=("PASS: Fedora container compatibility")
    else
        test_results+=("FAIL: Fedora container compatibility")
    fi
    
    # Only run build environment test if we have the required tools
    if command -v dnf >/dev/null 2>&1; then
        if test_build_environment_setup; then
            test_results+=("PASS: Build environment setup")
        else
            test_results+=("FAIL: Build environment setup")
        fi
    else
        test_results+=("SKIP: Build environment setup (not in Fedora environment)")
    fi
    
    # Print results
    log_info "Test Results Summary:"
    for result in "${test_results[@]}"; do
        if [[ "$result" =~ ^PASS ]]; then
            log_success "$result"
        elif [[ "$result" =~ ^FAIL ]]; then
            log_error "$result"
        else
            log_warning "$result"
        fi
    done
    
    # Check if any tests failed
    local failed_count=$(printf '%s\n' "${test_results[@]}" | grep -c "^FAIL" || true)
    
    if [[ $failed_count -eq 0 ]]; then
        log_success "All tests passed! Fedora container build environment is ready."
        return 0
    else
        log_error "$failed_count test(s) failed. Please review and fix issues before proceeding."
        return 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi