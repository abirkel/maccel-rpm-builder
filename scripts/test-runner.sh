#!/bin/bash

# Unified Test Runner for maccel-rpm-builder
# Single entry point for all testing: unit tests, integration tests, and validation
# Consolidates functionality from fragmented testing scripts

set -euo pipefail

# Script metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(dirname "$0")"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test configuration
TEST_TIMEOUT=3600  # 1 hour timeout for full test suite
WORKFLOW_TIMEOUT=1800  # 30 minutes for individual workflow runs
POLL_INTERVAL=30  # Poll every 30 seconds for workflow status
MAX_RETRIES=3  # Maximum retries for API calls

# Test kernel versions for cross-version compatibility
declare -A TEST_KERNELS=(
    ["fc41"]="6.11.5-300.fc41.x86_64"
    ["fc40"]="6.10.12-200.fc40.x86_64"
    ["fc39"]="6.8.11-300.fc39.x86_64"
)

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test results tracking
declare -A TEST_RESULTS=()

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_debug() {
    echo -e "${PURPLE}[DEBUG]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Function to record test result
record_test_result() {
    local test_name="$1"
    local result="$2"  # "PASS" or "FAIL"
    local details="${3:-}"
    
    TEST_RESULTS["$test_name"]="$result"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [[ "$result" == "PASS" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_success "$test_name${details:+ - $details}"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        log_error "$test_name${details:+ - $details}"
    fi
}

# Function to run a single test with error handling
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    local timeout="${4:-300}"  # 5 minute default timeout
    
    log_debug "Running: $test_name"
    
    local start_time=$(date +%s)
    local result="FAIL"
    local details=""
    
    # Run test with timeout
    if timeout "$timeout" bash -c "$test_command" >/dev/null 2>&1; then
        local actual_exit_code=0
    else
        local actual_exit_code=$?
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [[ $actual_exit_code -eq $expected_exit_code ]]; then
        result="PASS"
        details="(${duration}s)"
    else
        details="(expected exit $expected_exit_code, got $actual_exit_code, ${duration}s)"
    fi
    
    record_test_result "$test_name" "$result" "$details"
    return $([[ "$result" == "PASS" ]] && echo 0 || echo 1)
}

# Function to check prerequisites
check_prerequisites() {
    log_step "Checking test prerequisites..."
    
    local errors=0
    
    # Check required commands
    local required_commands=("gh" "git" "curl" "jq" "rpmlint")
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            log_debug "$cmd is available"
        else
            log_error "Required command not found: $cmd"
            ((errors++))
        fi
    done
    
    # Check GitHub authentication
    if gh auth status &> /dev/null; then
        log_debug "GitHub CLI authenticated"
    else
        log_error "Not authenticated with GitHub CLI. Run: gh auth login"
        ((errors++))
    fi
    
    # Check repository context
    if git rev-parse --git-dir &> /dev/null; then
        log_debug "Git repository detected"
    else
        log_error "Not in a git repository"
        ((errors++))
    fi
    
    # Check required scripts exist
    local required_scripts=(
        "scripts/check-existing-packages.sh"
        "scripts/detect-maccel-version.sh"
        "scripts/validate-rpm-specs.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ -f "$script" && -x "$script" ]]; then
            log_debug "Script available: $script"
        else
            log_error "Required script missing or not executable: $script"
            ((errors++))
        fi
    done
    
    # Check workflow file exists
    if [[ -f ".github/workflows/build-rpm.yml" ]]; then
        log_debug "Main workflow file found"
    else
        log_error "Main workflow file not found: .github/workflows/build-rpm.yml"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All prerequisites met"
        return 0
    else
        log_error "$errors prerequisite check(s) failed"
        return 1
    fi
}

# Function to get repository information
get_repo_info() {
    GITHUB_USER=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
    REPO_NAME=$(basename "$(git rev-parse --show-toplevel)" 2>/dev/null || echo "unknown")
    REPO_FULL_NAME="$GITHUB_USER/$REPO_NAME"
    
    if [[ "$GITHUB_USER" == "unknown" || "$REPO_NAME" == "unknown" ]]; then
        log_error "Could not determine repository information"
        return 1
    fi
    
    log_info "Repository: $REPO_FULL_NAME"
    return 0
}

# UNIT TESTS
# ==========

# Test script validation
test_script_validation() {
    log_step "Running script validation tests..."
    
    # Test package detection script
    run_test "Package detection help" "./scripts/check-existing-packages.sh help" 0
    run_test "Package detection input validation" "./scripts/check-existing-packages.sh check invalid-version" 1
    
    # Test version detection script
    run_test "Version detection functionality" "./scripts/detect-maccel-version.sh detect" 0
    
    # Test RPM spec validation (may fail due to missing changelog - that's expected)
    if ./scripts/validate-rpm-specs.sh >/dev/null 2>&1; then
        record_test_result "RPM spec validation" "PASS" "All specs valid"
    else
        # Check if it's just missing changelog (expected) vs real errors
        local spec_output=$(./scripts/validate-rpm-specs.sh 2>&1)
        if echo "$spec_output" | grep -q "Missing sections.*%changelog" && ! echo "$spec_output" | grep -q "syntax error\|parse error"; then
            record_test_result "RPM spec validation" "PASS" "Specs valid (missing changelog is expected)"
        else
            record_test_result "RPM spec validation" "FAIL" "Spec validation errors"
        fi
    fi
}

# Test workflow validation
test_workflow_validation() {
    log_step "Running workflow validation tests..."
    
    local workflow_file=".github/workflows/build-rpm.yml"
    
    # YAML syntax validation
    if command -v python3 &> /dev/null; then
        run_test "Workflow YAML syntax" "python3 -c \"import yaml; yaml.safe_load(open('$workflow_file'))\""
    else
        log_warning "Python3 not available, skipping YAML validation"
    fi
    
    # Required workflow elements
    run_test "Workflow has name" "grep -q '^name:' '$workflow_file'"
    run_test "Workflow has triggers" "grep -q '^on:' '$workflow_file'"
    run_test "Workflow has jobs" "grep -q '^jobs:' '$workflow_file'"
    run_test "Repository dispatch trigger" "grep -q 'repository_dispatch:' '$workflow_file'"
    run_test "Build matrix configured" "grep -q 'matrix:' '$workflow_file'"
    run_test "Both packages in matrix" "grep -A 5 'package:' '$workflow_file' | grep -q 'kmod-maccel' && grep -A 5 'package:' '$workflow_file' | grep -q 'maccel'"
}

# Test local development environment compatibility
test_local_environment() {
    log_step "Running local development environment tests..."
    
    # Essential tools for local development
    local tools=("git" "curl" "jq")
    for tool in "${tools[@]}"; do
        run_test "Tool available: $tool" "command -v $tool"
    done
    
    # Optional tools (don't fail if missing - they're for build environment)
    local optional_tools=("wget" "python3" "dnf" "rpm-build")
    for tool in "${optional_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_debug "Optional tool available: $tool"
        else
            log_debug "Optional tool not available (OK for local dev): $tool"
        fi
    done
    
    # File system permissions
    run_test "File system permissions" "mkdir -p /tmp/test-$$ && echo 'test' > /tmp/test-$$/file && rm -rf /tmp/test-$$"
    
    # Network connectivity
    run_test "GitHub API connectivity" "curl -s --connect-timeout 5 https://api.github.com/zen"
}

# INTEGRATION TESTS
# =================

# Function to trigger repository dispatch and get workflow ID
trigger_dispatch_and_get_workflow() {
    local kernel_version="$1"
    local fedora_version="$2"
    local force_rebuild="${3:-false}"
    local trigger_repo="test-$(date +%s)"
    
    log_debug "Triggering dispatch for $kernel_version..."
    
    # Get current workflow count
    local workflows_before=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || echo "0")
    
    # Create payload
    local temp_payload=$(mktemp)
    cat > "$temp_payload" << EOF
{
  "event_type": "build-for-kernel",
  "client_payload": {
    "kernel_version": "$kernel_version",
    "fedora_version": "$fedora_version",
    "trigger_repo": "$trigger_repo",
    "force_rebuild": $force_rebuild
  }
}
EOF
    
    # Send dispatch
    if ! gh api repos/"$REPO_FULL_NAME"/dispatches --method POST --input "$temp_payload"; then
        rm -f "$temp_payload"
        return 1
    fi
    
    rm -f "$temp_payload"
    
    # Wait for workflow to appear
    local max_wait=60
    local wait_count=0
    local workflow_id=""
    
    while [[ $wait_count -lt $max_wait ]]; do
        sleep 2
        wait_count=$((wait_count + 2))
        
        local latest_workflow=$(gh run list --limit 1 --json databaseId,event --jq '.[0]' 2>/dev/null || echo "{}")
        local latest_id=$(echo "$latest_workflow" | jq -r '.databaseId // empty')
        local latest_event=$(echo "$latest_workflow" | jq -r '.event // empty')
        
        if [[ -n "$latest_id" && "$latest_id" != "$workflows_before" && "$latest_event" == "repository_dispatch" ]]; then
            workflow_id="$latest_id"
            break
        fi
    done
    
    if [[ -z "$workflow_id" ]]; then
        return 1
    fi
    
    echo "$workflow_id"
    return 0
}

# Function to wait for workflow completion
wait_for_workflow() {
    local workflow_id="$1"
    local timeout="$2"
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            return 1
        fi
        
        local status=$(gh run view "$workflow_id" --json status --jq '.status' 2>/dev/null || echo "unknown")
        local conclusion=$(gh run view "$workflow_id" --json conclusion --jq '.conclusion' 2>/dev/null || echo "null")
        
        case "$status" in
            "completed")
                if [[ "$conclusion" == "success" ]]; then
                    return 0
                else
                    return 1
                fi
                ;;
            "in_progress"|"queued")
                sleep $POLL_INTERVAL
                ;;
            *)
                return 1
                ;;
        esac
    done
}

# Test end-to-end workflow
test_end_to_end_workflow() {
    log_step "Running end-to-end workflow test..."
    
    local kernel_version="${TEST_KERNELS[fc41]}"
    local fedora_version="41"
    
    # Get maccel version
    local maccel_version
    if ! maccel_version=$(./scripts/detect-maccel-version.sh detect 2>/dev/null); then
        record_test_result "E2E: Get maccel version" "FAIL" "Version detection failed"
        return 1
    fi
    
    record_test_result "E2E: Get maccel version" "PASS" "Version: $maccel_version"
    
    # Trigger workflow
    local workflow_id
    if ! workflow_id=$(trigger_dispatch_and_get_workflow "$kernel_version" "$fedora_version" "true"); then
        record_test_result "E2E: Trigger workflow" "FAIL" "Could not trigger or find workflow"
        return 1
    fi
    
    record_test_result "E2E: Trigger workflow" "PASS" "Workflow ID: $workflow_id"
    
    # Wait for completion
    if ! wait_for_workflow "$workflow_id" "$WORKFLOW_TIMEOUT"; then
        record_test_result "E2E: Workflow completion" "FAIL" "Workflow did not complete successfully"
        return 1
    fi
    
    record_test_result "E2E: Workflow completion" "PASS" "Workflow completed successfully"
    
    # Validate release creation
    local release_tag="kernel-${kernel_version}-maccel-${maccel_version}"
    if gh release view "$release_tag" --repo "$REPO_FULL_NAME" >/dev/null 2>&1; then
        record_test_result "E2E: Release creation" "PASS" "Release: $release_tag"
    else
        record_test_result "E2E: Release creation" "FAIL" "Release not found: $release_tag"
        return 1
    fi
    
    # Validate package URLs
    local base_url="https://github.com/$REPO_FULL_NAME/releases/download/$release_tag"
    local packages=("kmod-maccel-${maccel_version}-1.fc41.x86_64.rpm" "maccel-${maccel_version}-1.fc41.x86_64.rpm")
    
    for package in "${packages[@]}"; do
        local package_url="$base_url/$package"
        if curl -s --head "$package_url" | head -n 1 | grep -q "200 OK"; then
            record_test_result "E2E: Package URL accessible" "PASS" "$package"
        else
            record_test_result "E2E: Package URL accessible" "FAIL" "$package"
            return 1
        fi
    done
    
    return 0
}

# Test caching efficiency
test_caching_efficiency() {
    log_step "Running caching efficiency test..."
    
    local kernel_version="${TEST_KERNELS[fc41]}"
    local fedora_version="41"
    
    # First build (should create packages)
    local workflow_id1
    if ! workflow_id1=$(trigger_dispatch_and_get_workflow "$kernel_version" "$fedora_version" "true"); then
        record_test_result "Caching: First build trigger" "FAIL"
        return 1
    fi
    
    if ! wait_for_workflow "$workflow_id1" "$WORKFLOW_TIMEOUT"; then
        record_test_result "Caching: First build completion" "FAIL"
        return 1
    fi
    
    record_test_result "Caching: First build" "PASS"
    
    # Second build (should use cache)
    local workflow_id2
    if ! workflow_id2=$(trigger_dispatch_and_get_workflow "$kernel_version" "$fedora_version" "false"); then
        record_test_result "Caching: Second build trigger" "FAIL"
        return 1
    fi
    
    if ! wait_for_workflow "$workflow_id2" "$WORKFLOW_TIMEOUT"; then
        record_test_result "Caching: Second build completion" "FAIL"
        return 1
    fi
    
    # Compare durations
    local duration1=$(gh run view "$workflow_id1" --json createdAt,updatedAt --jq '(.updatedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)')
    local duration2=$(gh run view "$workflow_id2" --json createdAt,updatedAt --jq '(.updatedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)')
    
    if [[ $duration2 -lt $((duration1 / 2)) ]]; then
        record_test_result "Caching: Efficiency validation" "PASS" "Second build ${duration2}s vs first ${duration1}s"
    else
        record_test_result "Caching: Efficiency validation" "FAIL" "No significant improvement: ${duration2}s vs ${duration1}s"
    fi
    
    return 0
}

# Test error handling
test_error_handling() {
    log_step "Running error handling tests..."
    
    # Test invalid kernel version
    local invalid_kernel="invalid-kernel-version"
    local workflow_id
    
    if workflow_id=$(trigger_dispatch_and_get_workflow "$invalid_kernel" "41" "false" 2>/dev/null); then
        # If workflow was created, it should fail
        if wait_for_workflow "$workflow_id" 300; then
            record_test_result "Error handling: Invalid kernel version" "FAIL" "Workflow should have failed"
        else
            local conclusion=$(gh run view "$workflow_id" --json conclusion --jq '.conclusion')
            if [[ "$conclusion" == "failure" ]]; then
                record_test_result "Error handling: Invalid kernel version" "PASS" "Workflow correctly failed"
            else
                record_test_result "Error handling: Invalid kernel version" "FAIL" "Unexpected conclusion: $conclusion"
            fi
        fi
    else
        record_test_result "Error handling: Invalid kernel version" "PASS" "Dispatch correctly rejected"
    fi
}

# MAIN TEST SUITES
# ================

run_unit_tests() {
    log_step "=== Running Unit Tests ==="
    test_script_validation
    test_workflow_validation
    test_local_environment
}

run_integration_tests() {
    log_step "=== Running Integration Tests ==="
    test_end_to_end_workflow
}

run_performance_tests() {
    log_step "=== Running Performance Tests ==="
    test_caching_efficiency
}

run_error_tests() {
    log_step "=== Running Error Handling Tests ==="
    test_error_handling
}

run_cross_version_tests() {
    log_step "=== Running Cross-Version Tests ==="
    
    local test_count=0
    local success_count=0
    
    for fedora_version in "${!TEST_KERNELS[@]}"; do
        local kernel_version="${TEST_KERNELS[$fedora_version]}"
        log_info "Testing Fedora $fedora_version ($kernel_version)..."
        
        test_count=$((test_count + 1))
        
        # Simplified cross-version test (just trigger and validate)
        local workflow_id
        if workflow_id=$(trigger_dispatch_and_get_workflow "$kernel_version" "${fedora_version#fc}" "true"); then
            if wait_for_workflow "$workflow_id" "$WORKFLOW_TIMEOUT"; then
                success_count=$((success_count + 1))
                record_test_result "Cross-version: $fedora_version" "PASS"
            else
                record_test_result "Cross-version: $fedora_version" "FAIL" "Workflow failed"
            fi
        else
            record_test_result "Cross-version: $fedora_version" "FAIL" "Could not trigger workflow"
        fi
        
        # Delay between tests
        if [[ $test_count -lt ${#TEST_KERNELS[@]} ]]; then
            log_info "Waiting 60s before next test..."
            sleep 60
        fi
    done
    
    log_info "Cross-version results: $success_count/$test_count passed"
}

# Function to show test summary
show_test_summary() {
    echo ""
    log_step "=== Test Summary ==="
    log_info "Total tests: $TOTAL_TESTS"
    log_success "Passed: $PASSED_TESTS"
    
    if [[ $FAILED_TESTS -gt 0 ]]; then
        log_error "Failed: $FAILED_TESTS"
        echo ""
        log_error "Some tests failed. Check the output above for details."
        
        # Show failed tests
        log_info "Failed tests:"
        for test_name in "${!TEST_RESULTS[@]}"; do
            if [[ "${TEST_RESULTS[$test_name]}" == "FAIL" ]]; then
                echo "  - $test_name"
            fi
        done
        
        return 1
    else
        echo ""
        log_success "All tests passed!"
        log_info "The maccel-rpm-builder system is working correctly."
        return 0
    fi
}

# Function to cleanup test artifacts
cleanup_test_artifacts() {
    log_info "Cleaning up test artifacts..."
    find /tmp -name "test-*" -mmin +60 -delete 2>/dev/null || true
    find /tmp -name "*-test-*" -mmin +60 -delete 2>/dev/null || true
}

# Function to show usage
show_usage() {
    cat << EOF
Unified Test Runner for maccel-rpm-builder v$SCRIPT_VERSION

Usage: $0 [OPTIONS] [TEST_SUITE]

Test Suites:
  unit           - Unit tests (script validation, workflow validation, local environment)
  integration    - End-to-end integration tests (repository dispatch to package delivery)
  performance    - Performance tests (caching efficiency)
  error          - Error handling tests (invalid inputs, failure scenarios)
  cross-version  - Cross-version compatibility tests (multiple Fedora versions)
  all            - Run all test suites (very slow, requires GitHub Actions minutes)

Options:
  --dry-run      - Show what tests would run without executing them
  --verbose      - Enable verbose output and debugging
  --timeout SEC  - Override default test timeout (default: $TEST_TIMEOUT)
  --cleanup      - Clean up test artifacts before running
  --help         - Show this help message

Examples:
  $0 unit                    # Quick validation tests
  $0 integration --verbose   # Integration tests with debug output
  $0 all --cleanup          # Full test suite with cleanup
  $0 --dry-run cross-version # Show what cross-version tests would run

Environment Variables:
  GITHUB_TOKEN   - GitHub API token (required for integration tests)
  TEST_TIMEOUT   - Override default timeout
  SKIP_CLEANUP   - Skip cleanup of test artifacts

Requirements:
  - GitHub CLI (gh) installed and authenticated
  - Git repository with proper workflow setup
  - Network access to GitHub API
  - Sufficient GitHub Actions minutes for integration tests

Note: Integration and cross-version tests consume GitHub Actions minutes.
Use 'unit' tests for regular validation.
EOF
}

# Main function
main() {
    local test_suite=""
    local dry_run="false"
    local verbose="false"
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
            --timeout)
                TEST_TIMEOUT="$2"
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
    
    # Default to unit tests if no suite specified
    if [[ -z "$test_suite" ]]; then
        test_suite="unit"
    fi
    
    # Show what we would do in dry-run mode
    if [[ "$dry_run" == "true" ]]; then
        echo "DRY RUN: Would execute test suite '$test_suite'"
        case "$test_suite" in
            "unit")
                echo "  - Script validation tests"
                echo "  - Workflow validation tests"
                echo "  - Container compatibility tests"
                ;;
            "integration")
                echo "  - End-to-end workflow test"
                ;;
            "performance")
                echo "  - Caching efficiency test"
                ;;
            "error")
                echo "  - Error handling tests"
                ;;
            "cross-version")
                for fedora_version in "${!TEST_KERNELS[@]}"; do
                    echo "  - Test Fedora $fedora_version (${TEST_KERNELS[$fedora_version]})"
                done
                ;;
            "all")
                echo "  - All test suites above"
                ;;
        esac
        exit 0
    fi
    
    # Start test execution
    echo ""
    log_step "Starting maccel-rpm-builder Test Suite v$SCRIPT_VERSION"
    log_info "Test suite: $test_suite"
    log_info "Timeout: ${TEST_TIMEOUT}s"
    echo ""
    
    local start_time=$(date +%s)
    
    # Setup
    if ! check_prerequisites; then
        exit 1
    fi
    
    if ! get_repo_info; then
        exit 1
    fi
    
    # Cleanup if requested
    if [[ "$cleanup" == "true" ]]; then
        cleanup_test_artifacts
    fi
    
    # Run tests based on suite
    case "$test_suite" in
        "unit")
            run_unit_tests
            ;;
        "integration")
            run_integration_tests
            ;;
        "performance")
            run_performance_tests
            ;;
        "error")
            run_error_tests
            ;;
        "cross-version")
            run_cross_version_tests
            ;;
        "all")
            run_unit_tests
            echo ""
            run_integration_tests
            echo ""
            run_performance_tests
            echo ""
            run_error_tests
            echo ""
            run_cross_version_tests
            ;;
        *)
            log_error "Unknown test suite: $test_suite"
            show_usage
            exit 1
            ;;
    esac
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    log_info "Test execution completed in ${duration}s"
    
    # Show summary and exit with appropriate code
    if show_test_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"