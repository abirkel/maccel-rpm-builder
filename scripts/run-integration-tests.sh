#!/bin/bash

# Integration Test Runner
# Orchestrates all integration tests for maccel-rpm-builder

set -euo pipefail

# Source configuration
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/test-config.sh"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[TEST RUNNER]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[TEST RUNNER]${NC} $1"
}

log_error() {
    echo -e "${RED}[TEST RUNNER]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[TEST RUNNER]${NC} $1"
}

# Test suite configuration
declare -A TEST_SUITES=(
    ["validation"]="Workflow and script validation"
    ["unit"]="Unit tests for individual components"
    ["integration"]="End-to-end integration tests"
    ["compatibility"]="Cross-version compatibility tests"
    ["performance"]="Performance and caching tests"
    ["error-handling"]="Error scenario testing"
)

# Function to show usage
show_usage() {
    cat << EOF
Integration Test Runner for maccel-rpm-builder

Usage: $0 [OPTIONS] [TEST_SUITE]

Test Suites:
  validation      - Validate workflows and scripts (fast)
  unit           - Run unit tests (fast)
  integration    - End-to-end integration tests (moderate)
  compatibility  - Cross-version compatibility (slow)
  performance    - Performance and caching tests (moderate)
  error-handling - Error scenario testing (fast)
  all            - Run all test suites (very slow)

Options:
  --dry-run      - Show what would be tested without running
  --verbose      - Enable verbose output
  --report FILE  - Generate test report to specified file
  --cleanup      - Clean up test artifacts before running
  --help         - Show this help message

Examples:
  $0 validation                    # Quick validation
  $0 integration --verbose         # Integration tests with verbose output
  $0 all --report test-report.json # Full test suite with report
  $0 --dry-run compatibility       # Show what compatibility tests would run

Environment Variables:
  GITHUB_TOKEN   - GitHub API token (required)
  TEST_TIMEOUT   - Override default test timeout
  SKIP_CLEANUP   - Skip cleanup of test artifacts
EOF
}

# Function to run test suite
run_test_suite() {
    local suite="$1"
    local dry_run="${2:-false}"
    
    log_info "Running test suite: $suite"
    
    case "$suite" in
        "validation")
            run_validation_tests "$dry_run"
            ;;
        "unit")
            run_unit_tests "$dry_run"
            ;;
        "integration")
            run_integration_tests "$dry_run"
            ;;
        "compatibility")
            run_compatibility_tests "$dry_run"
            ;;
        "performance")
            run_performance_tests "$dry_run"
            ;;
        "error-handling")
            run_error_handling_tests "$dry_run"
            ;;
        "all")
            run_all_tests "$dry_run"
            ;;
        *)
            log_error "Unknown test suite: $suite"
            return 1
            ;;
    esac
}

# Individual test suite functions
run_validation_tests() {
    local dry_run="$1"
    
    if [[ "$dry_run" == "true" ]]; then
        echo "Would run: Workflow validation tests"
        echo "Would run: Script validation tests"
        return 0
    fi
    
    log_info "Running validation tests..."
    
    if "$SCRIPT_DIR/test-workflow-validation.sh"; then
        record_test_result "validation_suite" "PASS"
    else
        record_test_result "validation_suite" "FAIL"
    fi
}

run_unit_tests() {
    local dry_run="$1"
    
    if [[ "$dry_run" == "true" ]]; then
        echo "Would run: Package detection tests"
        echo "Would run: Version detection tests"
        echo "Would run: Workflow validation tests"
        return 0
    fi
    
    log_info "Running unit tests..."
    
    local unit_test_scripts=(
        "test-package-detection.sh"
        "validate-workflows.sh"
    )
    
    for script in "${unit_test_scripts[@]}"; do
        if [[ -f "$SCRIPT_DIR/$script" ]]; then
            if "$SCRIPT_DIR/$script"; then
                record_test_result "unit_${script}" "PASS"
            else
                record_test_result "unit_${script}" "FAIL"
            fi
        fi
    done
}

run_integration_tests() {
    local dry_run="$1"
    
    if [[ "$dry_run" == "true" ]]; then
        echo "Would run: End-to-end workflow test"
        echo "Would run: Package delivery validation"
        echo "Would run: Release creation test"
        return 0
    fi
    
    log_info "Running integration tests..."
    
    if "$SCRIPT_DIR/integration-test.sh" quick; then
        record_test_result "integration_suite" "PASS"
    else
        record_test_result "integration_suite" "FAIL"
    fi
}

run_compatibility_tests() {
    local dry_run="$1"
    
    if [[ "$dry_run" == "true" ]]; then
        for fedora_version in "${!TEST_KERNEL_VERSIONS[@]}"; do
            echo "Would test: ${TEST_KERNEL_VERSIONS[$fedora_version]}"
        done
        return 0
    fi
    
    log_info "Running compatibility tests..."
    
    if "$SCRIPT_DIR/integration-test.sh" cross-version; then
        record_test_result "compatibility_suite" "PASS"
    else
        record_test_result "compatibility_suite" "FAIL"
    fi
}

run_performance_tests() {
    local dry_run="$1"
    
    if [[ "$dry_run" == "true" ]]; then
        echo "Would run: Caching efficiency test"
        echo "Would run: Build time measurement"
        return 0
    fi
    
    log_info "Running performance tests..."
    
    if "$SCRIPT_DIR/integration-test.sh" caching; then
        record_test_result "performance_suite" "PASS"
    else
        record_test_result "performance_suite" "FAIL"
    fi
}

run_error_handling_tests() {
    local dry_run="$1"
    
    if [[ "$dry_run" == "true" ]]; then
        echo "Would run: Invalid input handling"
        echo "Would run: Build failure scenarios"
        return 0
    fi
    
    log_info "Running error handling tests..."
    
    if "$SCRIPT_DIR/integration-test.sh" error-handling; then
        record_test_result "error_handling_suite" "PASS"
    else
        record_test_result "error_handling_suite" "FAIL"
    fi
}

run_all_tests() {
    local dry_run="$1"
    
    local all_suites=("validation" "unit" "integration" "performance" "error-handling" "compatibility")
    
    for suite in "${all_suites[@]}"; do
        run_test_suite "$suite" "$dry_run"
        
        # Add delay between test suites to avoid rate limiting
        if [[ "$dry_run" == "false" && "$suite" != "compatibility" ]]; then
            log_info "Waiting 30s before next test suite..."
            sleep 30
        fi
    done
}

# Main function
main() {
    local test_suite=""
    local dry_run="false"
    local verbose="false"
    local report_file=""
    local cleanup="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run="true"
                shift
                ;;
            --verbose)
                verbose="true"
                set -x
                shift
                ;;
            --report)
                report_file="$2"
                shift 2
                ;;
            --cleanup)
                cleanup="true"
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$test_suite" ]]; then
                    test_suite="$1"
                else
                    log_error "Multiple test suites specified"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Default to validation if no suite specified
    if [[ -z "$test_suite" ]]; then
        test_suite="validation"
    fi
    
    # Validate environment
    if ! validate_test_environment; then
        log_error "Test environment validation failed"
        exit 1
    fi
    
    # Get repository information
    if ! get_repository_info; then
        log_error "Could not get repository information"
        exit 1
    fi
    
    # Cleanup if requested
    if [[ "$cleanup" == "true" ]]; then
        cleanup_test_artifacts
    fi
    
    # Check GitHub rate limit
    if [[ "$dry_run" == "false" ]]; then
        check_github_rate_limit || log_warning "GitHub rate limit is low"
    fi
    
    # Run tests
    log_info "Starting test execution..."
    log_info "Test suite: $test_suite"
    log_info "Dry run: $dry_run"
    log_info "Repository: $GITHUB_REPO_FULL"
    echo ""
    
    local start_time=$(date +%s)
    
    if run_test_suite "$test_suite" "$dry_run"; then
        log_success "Test suite completed successfully"
    else
        log_error "Test suite failed"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    log_info "Test execution completed in ${duration}s"
    get_test_summary
    
    # Generate report if requested
    if [[ -n "$report_file" ]]; then
        generate_test_report "$report_file"
    fi
    
    # Return appropriate exit code
    if [[ $FAILED_TESTS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"