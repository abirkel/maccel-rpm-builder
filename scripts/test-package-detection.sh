#!/bin/bash

# Test script for package detection logic
# This script tests the check-existing-packages.sh functionality

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[TEST INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[TEST PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[TEST WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[TEST FAIL]${NC} $1"
}

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    log_info "Running test: $test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        local actual_exit_code=0
    else
        local actual_exit_code=$?
    fi
    
    if [[ $actual_exit_code -eq $expected_exit_code ]]; then
        log_success "$test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "$test_name (expected exit code $expected_exit_code, got $actual_exit_code)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Function to test script help
test_help() {
    log_info "Testing help functionality..."
    
    run_test "Help command works" "./scripts/check-existing-packages.sh help" 0
    run_test "Help flag works" "./scripts/check-existing-packages.sh --help" 0
    run_test "Help short flag works" "./scripts/check-existing-packages.sh -h" 0
}

# Function to test input validation
test_input_validation() {
    log_info "Testing input validation..."
    
    # Test invalid kernel version formats
    run_test "Rejects invalid kernel version (no fc)" "./scripts/check-existing-packages.sh check 6.11.5-300.x86_64" 1
    run_test "Rejects invalid kernel version (no arch)" "./scripts/check-existing-packages.sh check 6.11.5-300.fc41" 1
    run_test "Rejects invalid kernel version (wrong format)" "./scripts/check-existing-packages.sh check invalid-version" 1
    
    # Test missing required arguments
    run_test "Rejects missing kernel version" "./scripts/check-existing-packages.sh check" 1
    run_test "Rejects missing arguments for info" "./scripts/check-existing-packages.sh info" 1
}

# Function to test release tag generation
test_release_tag_generation() {
    log_info "Testing release tag generation..."
    
    # Test release tag generation
    local expected_tag="kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0"
    local actual_tag=""
    actual_tag=$(./scripts/check-existing-packages.sh release-tag 6.11.5-300.fc41.x86_64 1.0.0 2>/dev/null || echo "")
    
    if [[ "$actual_tag" == "$expected_tag" ]]; then
        log_success "Release tag generation produces correct format"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "Release tag generation failed (expected: $expected_tag, got: $actual_tag)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Function to test version detection integration
test_version_detection() {
    log_info "Testing version detection integration..."
    
    # Test that the script can detect maccel version
    if ./scripts/detect-maccel-version.sh detect >/dev/null 2>&1; then
        log_success "Version detection script is accessible and working"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "Version detection script failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Function to test package checking (without GitHub API)
test_package_checking_offline() {
    log_info "Testing package checking logic (offline mode)..."
    
    # Test with a valid kernel version format (will fail due to no GitHub token, but should validate input)
    local test_kernel="6.11.5-300.fc41.x86_64"
    local test_maccel="1.0.0"
    
    # This should fail because we don't have GitHub access in test, but it should validate inputs first
    run_test "Package check handles missing GitHub access gracefully" "./scripts/check-existing-packages.sh check $test_kernel $test_maccel" 1
}

# Function to show test summary
show_test_summary() {
    echo ""
    log_info "=== Test Summary ==="
    log_info "Tests run: $TESTS_RUN"
    log_success "Tests passed: $TESTS_PASSED"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        log_error "Tests failed: $TESTS_FAILED"
        echo ""
        log_error "Some tests failed. Please review the output above."
        return 1
    else
        echo ""
        log_success "All tests passed!"
        return 0
    fi
}

# Main test function
main() {
    log_info "Starting package detection tests..."
    echo ""
    
    # Check if the script exists
    if [[ ! -f "./scripts/check-existing-packages.sh" ]]; then
        log_error "check-existing-packages.sh script not found"
        exit 1
    fi
    
    # Check if the script is executable
    if [[ ! -x "./scripts/check-existing-packages.sh" ]]; then
        log_error "check-existing-packages.sh script is not executable"
        exit 1
    fi
    
    # Run tests
    test_help
    test_input_validation
    test_release_tag_generation
    test_version_detection
    test_package_checking_offline
    
    # Show summary
    show_test_summary
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi