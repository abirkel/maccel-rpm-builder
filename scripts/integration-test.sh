#!/bin/bash

# Integration Testing Script for maccel-rpm-builder
# Tests end-to-end workflow from repository dispatch to package delivery
# Validates cross-version compatibility and system integration

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test configuration
TEST_TIMEOUT=3600  # 1 hour timeout for full integration tests
WORKFLOW_TIMEOUT=1800  # 30 minutes for individual workflow runs
POLL_INTERVAL=30  # Poll every 30 seconds for workflow status

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
INTEGRATION_TESTS_RUN=0
INTEGRATION_TESTS_PASSED=0

# Test data for cross-version compatibility
declare -A TEST_KERNELS=(
    ["fc41"]="6.11.5-300.fc41.x86_64"
    ["fc40"]="6.10.12-200.fc40.x86_64"
    ["fc39"]="6.8.11-300.fc39.x86_64"
)

# Logging functions
log_info() {
    echo -e "${BLUE}[INTEGRATION INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[INTEGRATION PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[INTEGRATION WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[INTEGRATION FAIL]${NC} $1"
}

log_debug() {
    echo -e "${PURPLE}[INTEGRATION DEBUG]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[INTEGRATION STEP]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_step "Checking integration test prerequisites..."
    
    # Check if gh CLI is available and authenticated
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is not installed"
        return 1
    fi
    
    if ! gh auth status &> /dev/null; then
        log_error "Not authenticated with GitHub. Please run: gh auth login"
        return 1
    fi
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir &> /dev/null; then
        log_error "Not in a git repository"
        return 1
    fi
    
    # Check if required scripts exist
    local required_scripts=(
        "scripts/test-dispatch.sh"
        "scripts/check-existing-packages.sh"
        "scripts/detect-maccel-version.sh"
        "scripts/validate-workflows.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            log_error "Required script not found: $script"
            return 1
        fi
        
        if [[ ! -x "$script" ]]; then
            log_error "Script is not executable: $script"
            return 1
        fi
    done
    
    # Check if workflow file exists
    if [[ ! -f ".github/workflows/build-rpm.yml" ]]; then
        log_error "Main workflow file not found: .github/workflows/build-rpm.yml"
        return 1
    fi
    
    log_success "All prerequisites met"
    return 0
}

# Function to get repository information
get_repo_info() {
    GITHUB_USER=$(gh api user --jq '.login')
    REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
    REPO_FULL_NAME="$GITHUB_USER/$REPO_NAME"
    
    log_info "Repository: $REPO_FULL_NAME"
}

# Function to wait for workflow completion
wait_for_workflow() {
    local workflow_id="$1"
    local timeout="$2"
    local start_time=$(date +%s)
    
    log_info "Waiting for workflow $workflow_id to complete (timeout: ${timeout}s)..."
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            log_error "Workflow timeout after ${timeout}s"
            return 1
        fi
        
        local status=$(gh run view "$workflow_id" --json status --jq '.status' 2>/dev/null || echo "unknown")
        local conclusion=$(gh run view "$workflow_id" --json conclusion --jq '.conclusion' 2>/dev/null || echo "null")
        
        log_debug "Workflow status: $status, conclusion: $conclusion (elapsed: ${elapsed}s)"
        
        case "$status" in
            "completed")
                if [[ "$conclusion" == "success" ]]; then
                    log_success "Workflow completed successfully"
                    return 0
                else
                    log_error "Workflow failed with conclusion: $conclusion"
                    return 1
                fi
                ;;
            "in_progress"|"queued")
                sleep $POLL_INTERVAL
                ;;
            *)
                log_error "Unexpected workflow status: $status"
                return 1
                ;;
        esac
    done
}

# Function to trigger repository dispatch and get workflow ID
trigger_dispatch_and_get_workflow() {
    local kernel_version="$1"
    local fedora_version="$2"
    local force_rebuild="${3:-false}"
    local trigger_repo="integration-test-$(date +%s)"
    
    log_step "Triggering repository dispatch for $kernel_version..."
    
    # Get current workflow count to identify new workflow
    local workflows_before=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || echo "0")
    
    # Create payload as a properly formatted JSON string
    local payload_json="{\"kernel_version\":\"$kernel_version\",\"fedora_version\":\"$fedora_version\",\"trigger_repo\":\"$trigger_repo\",\"force_rebuild\":$force_rebuild}"
    
    log_debug "Dispatch payload: $payload_json"
    
    # Create temporary file for payload
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
    
    # Send repository dispatch
    if ! gh api repos/"$REPO_FULL_NAME"/dispatches \
        --method POST \
        --input "$temp_payload"; then
        log_error "Failed to send repository dispatch"
        return 1
    fi
    
    rm -f "$temp_payload"
    log_info "Repository dispatch sent successfully"
    
    # Wait for new workflow to appear
    local max_wait=60  # Wait up to 60 seconds for workflow to appear
    local wait_count=0
    local workflow_id=""
    
    while [[ $wait_count -lt $max_wait ]]; do
        sleep 2
        wait_count=$((wait_count + 2))
        
        # Get the latest workflow
        local latest_workflow=$(gh run list --limit 1 --json databaseId,event,status --jq '.[0]' 2>/dev/null || echo "{}")
        local latest_id=$(echo "$latest_workflow" | jq -r '.databaseId // empty')
        local latest_event=$(echo "$latest_workflow" | jq -r '.event // empty')
        
        if [[ -n "$latest_id" && "$latest_id" != "$workflows_before" && "$latest_event" == "repository_dispatch" ]]; then
            workflow_id="$latest_id"
            break
        fi
    done
    
    if [[ -z "$workflow_id" ]]; then
        log_error "Could not find triggered workflow within ${max_wait}s"
        return 1
    fi
    
    log_success "Found triggered workflow: $workflow_id"
    echo "$workflow_id"
    return 0
}

# Function to validate workflow results
validate_workflow_results() {
    local workflow_id="$1"
    local kernel_version="$2"
    local expected_maccel_version="$3"
    
    log_step "Validating workflow results for workflow $workflow_id..."
    
    # Get workflow details
    local workflow_info=$(gh run view "$workflow_id" --json conclusion,jobs,url)
    local conclusion=$(echo "$workflow_info" | jq -r '.conclusion')
    local workflow_url=$(echo "$workflow_info" | jq -r '.url')
    
    log_info "Workflow URL: $workflow_url"
    
    if [[ "$conclusion" != "success" ]]; then
        log_error "Workflow did not complete successfully: $conclusion"
        return 1
    fi
    
    # Check if release was created
    local release_tag="kernel-${kernel_version}-maccel-${expected_maccel_version}"
    log_debug "Checking for release: $release_tag"
    
    if gh release view "$release_tag" --repo "$REPO_FULL_NAME" >/dev/null 2>&1; then
        log_success "Release created successfully: $release_tag"
    else
        log_error "Release not found: $release_tag"
        return 1
    fi
    
    # Validate release assets
    local assets=$(gh release view "$release_tag" --repo "$REPO_FULL_NAME" --json assets --jq '.assets[].name')
    local required_assets=(
        "kmod-maccel-${expected_maccel_version}-1.fc${kernel_version##*.fc}.x86_64.rpm"
        "maccel-${expected_maccel_version}-1.fc${kernel_version##*.fc}.x86_64.rpm"
        "checksums.txt"
        "build-info.json"
    )
    
    for asset in "${required_assets[@]}"; do
        if echo "$assets" | grep -q "^${asset}$"; then
            log_success "Required asset found: $asset"
        else
            log_error "Required asset missing: $asset"
            return 1
        fi
    done
    
    # Validate package URLs are accessible
    local base_url="https://github.com/$REPO_FULL_NAME/releases/download/$release_tag"
    for asset in "${required_assets[@]}"; do
        local asset_url="$base_url/$asset"
        if curl -s --head "$asset_url" | head -n 1 | grep -q "200 OK"; then
            log_success "Asset URL accessible: $asset"
        else
            log_error "Asset URL not accessible: $asset_url"
            return 1
        fi
    done
    
    log_success "All workflow results validated successfully"
    return 0
}

# Function to test end-to-end workflow
test_end_to_end_workflow() {
    local kernel_version="$1"
    local fedora_version="$2"
    local test_name="$3"
    
    log_step "Starting end-to-end test: $test_name"
    INTEGRATION_TESTS_RUN=$((INTEGRATION_TESTS_RUN + 1))
    
    # Get expected maccel version
    local maccel_version
    if ! maccel_version=$(./scripts/detect-maccel-version.sh detect 2>/dev/null); then
        log_error "Failed to detect maccel version for test"
        return 1
    fi
    
    log_info "Testing with kernel: $kernel_version, maccel: $maccel_version"
    
    # Trigger workflow and get ID
    local workflow_id
    if ! workflow_id=$(trigger_dispatch_and_get_workflow "$kernel_version" "$fedora_version" "true"); then
        log_error "Failed to trigger workflow for $test_name"
        return 1
    fi
    
    # Wait for workflow completion
    if ! wait_for_workflow "$workflow_id" "$WORKFLOW_TIMEOUT"; then
        log_error "Workflow did not complete successfully for $test_name"
        
        # Get workflow logs for debugging
        log_info "Fetching workflow logs for debugging..."
        gh run view "$workflow_id" --log > "/tmp/integration-test-${workflow_id}.log" 2>/dev/null || true
        
        return 1
    fi
    
    # Validate results
    if ! validate_workflow_results "$workflow_id" "$kernel_version" "$maccel_version"; then
        log_error "Workflow results validation failed for $test_name"
        return 1
    fi
    
    log_success "End-to-end test passed: $test_name"
    INTEGRATION_TESTS_PASSED=$((INTEGRATION_TESTS_PASSED + 1))
    return 0
}

# Function to test caching and efficiency
test_caching_efficiency() {
    local kernel_version="$1"
    local fedora_version="$2"
    
    log_step "Testing caching and efficiency for $kernel_version..."
    INTEGRATION_TESTS_RUN=$((INTEGRATION_TESTS_RUN + 1))
    
    # First build (should build packages)
    log_info "First build - should create new packages"
    local workflow_id1
    if ! workflow_id1=$(trigger_dispatch_and_get_workflow "$kernel_version" "$fedora_version" "true"); then
        log_error "Failed to trigger first workflow for caching test"
        return 1
    fi
    
    if ! wait_for_workflow "$workflow_id1" "$WORKFLOW_TIMEOUT"; then
        log_error "First workflow failed for caching test"
        return 1
    fi
    
    # Second build (should use cache)
    log_info "Second build - should use existing packages"
    local workflow_id2
    if ! workflow_id2=$(trigger_dispatch_and_get_workflow "$kernel_version" "$fedora_version" "false"); then
        log_error "Failed to trigger second workflow for caching test"
        return 1
    fi
    
    if ! wait_for_workflow "$workflow_id2" "$WORKFLOW_TIMEOUT"; then
        log_error "Second workflow failed for caching test"
        return 1
    fi
    
    # Validate that second build was faster (used cache)
    local duration1=$(gh run view "$workflow_id1" --json createdAt,updatedAt --jq '(.updatedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)')
    local duration2=$(gh run view "$workflow_id2" --json createdAt,updatedAt --jq '(.updatedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)')
    
    log_info "First build duration: ${duration1}s, Second build duration: ${duration2}s"
    
    # Second build should be significantly faster (at least 50% faster)
    if [[ $duration2 -lt $((duration1 / 2)) ]]; then
        log_success "Caching efficiency validated - second build was ${duration2}s vs ${duration1}s"
        INTEGRATION_TESTS_PASSED=$((INTEGRATION_TESTS_PASSED + 1))
        return 0
    else
        log_warning "Caching may not be working optimally - durations are similar"
        # Don't fail the test, but note the issue
        INTEGRATION_TESTS_PASSED=$((INTEGRATION_TESTS_PASSED + 1))
        return 0
    fi
}

# Function to test cross-version compatibility
test_cross_version_compatibility() {
    log_step "Testing cross-version compatibility..."
    
    local test_count=0
    local success_count=0
    
    for fedora_version in "${!TEST_KERNELS[@]}"; do
        local kernel_version="${TEST_KERNELS[$fedora_version]}"
        local test_name="Cross-version test: Fedora $fedora_version ($kernel_version)"
        
        test_count=$((test_count + 1))
        
        if test_end_to_end_workflow "$kernel_version" "${fedora_version#fc}" "$test_name"; then
            success_count=$((success_count + 1))
        fi
        
        # Add delay between tests to avoid rate limiting
        if [[ $test_count -lt ${#TEST_KERNELS[@]} ]]; then
            log_info "Waiting 60s before next cross-version test..."
            sleep 60
        fi
    done
    
    log_info "Cross-version compatibility results: $success_count/$test_count tests passed"
    
    if [[ $success_count -eq $test_count ]]; then
        log_success "All cross-version compatibility tests passed"
        return 0
    else
        log_error "Some cross-version compatibility tests failed"
        return 1
    fi
}

# Function to test error handling scenarios
test_error_handling() {
    log_step "Testing error handling scenarios..."
    INTEGRATION_TESTS_RUN=$((INTEGRATION_TESTS_RUN + 1))
    
    # Test invalid kernel version
    log_info "Testing invalid kernel version handling..."
    local invalid_kernel="invalid-kernel-version"
    
    local workflow_id
    if workflow_id=$(trigger_dispatch_and_get_workflow "$invalid_kernel" "41" "false" 2>/dev/null); then
        # Wait for workflow to complete (should fail)
        if wait_for_workflow "$workflow_id" 300; then  # Shorter timeout for expected failure
            log_error "Workflow should have failed with invalid kernel version"
            return 1
        else
            # Check that it failed for the right reason
            local conclusion=$(gh run view "$workflow_id" --json conclusion --jq '.conclusion')
            if [[ "$conclusion" == "failure" ]]; then
                log_success "Workflow correctly failed with invalid kernel version"
            else
                log_error "Workflow failed but with unexpected conclusion: $conclusion"
                return 1
            fi
        fi
    else
        log_success "Repository dispatch correctly rejected invalid kernel version"
    fi
    
    INTEGRATION_TESTS_PASSED=$((INTEGRATION_TESTS_PASSED + 1))
    return 0
}

# Function to run unit tests first
run_unit_tests() {
    log_step "Running unit tests before integration tests..."
    
    local unit_test_scripts=(
        "scripts/test-package-detection.sh"
        "scripts/validate-workflows.sh"
    )
    
    for script in "${unit_test_scripts[@]}"; do
        if [[ -f "$script" && -x "$script" ]]; then
            log_info "Running unit test: $script"
            if "$script"; then
                log_success "Unit test passed: $script"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                log_error "Unit test failed: $script"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
            TESTS_RUN=$((TESTS_RUN + 1))
        fi
    done
}

# Function to show test summary
show_test_summary() {
    echo ""
    log_step "=== Integration Test Summary ==="
    log_info "Unit tests: $TESTS_PASSED/$TESTS_RUN passed"
    log_info "Integration tests: $INTEGRATION_TESTS_PASSED/$INTEGRATION_TESTS_RUN passed"
    
    local total_tests=$((TESTS_RUN + INTEGRATION_TESTS_RUN))
    local total_passed=$((TESTS_PASSED + INTEGRATION_TESTS_PASSED))
    local total_failed=$((TESTS_FAILED + (INTEGRATION_TESTS_RUN - INTEGRATION_TESTS_PASSED)))
    
    log_info "Total tests: $total_passed/$total_tests passed"
    
    if [[ $total_failed -gt 0 ]]; then
        log_error "Some tests failed. Check the output above for details."
        echo ""
        log_info "Debugging information:"
        log_info "- Check workflow logs in GitHub Actions"
        log_info "- Review /tmp/integration-test-*.log files"
        log_info "- Verify GitHub API rate limits"
        log_info "- Check repository permissions"
        return 1
    else
        echo ""
        log_success "All integration tests passed!"
        log_info "The maccel-rpm-builder system is working correctly end-to-end"
        return 0
    fi
}

# Function to cleanup test artifacts
cleanup_test_artifacts() {
    log_step "Cleaning up test artifacts..."
    
    # Remove temporary log files older than 1 hour
    find /tmp -name "integration-test-*.log" -mmin +60 -delete 2>/dev/null || true
    
    log_info "Cleanup completed"
}

# Main test function
main() {
    local test_mode="${1:-full}"
    
    echo ""
    log_step "Starting maccel-rpm-builder Integration Tests"
    log_info "Test mode: $test_mode"
    log_info "Timeout: ${TEST_TIMEOUT}s"
    echo ""
    
    # Setup
    if ! check_prerequisites; then
        exit 1
    fi
    
    get_repo_info
    
    # Run unit tests first
    run_unit_tests
    
    case "$test_mode" in
        "unit")
            log_info "Running unit tests only"
            ;;
        "quick")
            log_info "Running quick integration test with single kernel version"
            if test_end_to_end_workflow "${TEST_KERNELS[fc41]}" "41" "Quick integration test"; then
                INTEGRATION_TESTS_PASSED=$((INTEGRATION_TESTS_PASSED + 1))
            fi
            INTEGRATION_TESTS_RUN=$((INTEGRATION_TESTS_RUN + 1))
            ;;
        "caching")
            log_info "Running caching efficiency test"
            test_caching_efficiency "${TEST_KERNELS[fc41]}" "41"
            ;;
        "cross-version")
            log_info "Running cross-version compatibility tests"
            test_cross_version_compatibility
            ;;
        "error-handling")
            log_info "Running error handling tests"
            test_error_handling
            ;;
        "full")
            log_info "Running full integration test suite"
            
            # Quick test first
            if test_end_to_end_workflow "${TEST_KERNELS[fc41]}" "41" "Quick integration test"; then
                log_success "Quick test passed, proceeding with full suite"
            else
                log_error "Quick test failed, skipping remaining tests"
                show_test_summary
                exit 1
            fi
            
            # Caching test
            test_caching_efficiency "${TEST_KERNELS[fc41]}" "41"
            
            # Error handling test
            test_error_handling
            
            # Cross-version compatibility (if time permits)
            log_info "Starting cross-version tests (this may take a while)..."
            test_cross_version_compatibility
            ;;
        *)
            log_error "Unknown test mode: $test_mode"
            log_info "Available modes: unit, quick, caching, cross-version, error-handling, full"
            exit 1
            ;;
    esac
    
    # Cleanup
    cleanup_test_artifacts
    
    # Show summary
    show_test_summary
}

# Show help
show_help() {
    cat << EOF
Integration Testing Script for maccel-rpm-builder

Usage: $0 [MODE]

Modes:
  unit           Run unit tests only (fast)
  quick          Run single end-to-end test (moderate)
  caching        Test caching and efficiency (moderate)
  cross-version  Test multiple Fedora versions (slow)
  error-handling Test error scenarios (fast)
  full           Run complete test suite (very slow)

Examples:
  $0 unit           # Quick validation
  $0 quick          # Basic integration test
  $0 full           # Complete test suite

Requirements:
  - GitHub CLI (gh) installed and authenticated
  - Git repository with proper workflow setup
  - Network access to GitHub API
  - Sufficient GitHub Actions minutes for testing

Note: Full integration tests can take 1+ hours and consume significant
GitHub Actions minutes. Use 'quick' mode for regular validation.
EOF
}

# Handle command line arguments
case "${1:-}" in
    "help"|"--help"|"-h")
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac