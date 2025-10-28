#!/bin/bash

# Integration Test Configuration
# Shared configuration and utilities for integration testing

# Test environment configuration
export INTEGRATION_TEST_TIMEOUT=3600  # 1 hour
export WORKFLOW_TIMEOUT=1800          # 30 minutes
export POLL_INTERVAL=30               # 30 seconds
export MAX_RETRIES=3                  # Maximum retries for API calls
export RATE_LIMIT_DELAY=60            # Delay between tests to avoid rate limiting

# Test kernel versions for cross-version compatibility
declare -gA TEST_KERNEL_VERSIONS=(
    ["fc41"]="6.11.5-300.fc41.x86_64"
    ["fc40"]="6.10.12-200.fc40.x86_64"
    ["fc39"]="6.8.11-300.fc39.x86_64"
)

# Expected package naming patterns
declare -gA PACKAGE_PATTERNS=(
    ["kmod"]="kmod-maccel-{VERSION}-1.fc{FEDORA}.{ARCH}.rpm"
    ["cli"]="maccel-{VERSION}-1.fc{FEDORA}.{ARCH}.rpm"
)

# Required release assets
declare -ga REQUIRED_ASSETS=(
    "checksums.txt"
    "build-info.json"
)

# Optional assets (may be present depending on configuration)
declare -ga OPTIONAL_ASSETS=(
    "signing-summary.json"
    "PACKAGE_VERIFICATION.md"
    "verification-report.txt"
    "sigstore-info.txt"
)

# GitHub API endpoints
export GITHUB_API_BASE="https://api.github.com"
export GITHUB_RELEASES_API="/repos/{OWNER}/{REPO}/releases"
export GITHUB_WORKFLOWS_API="/repos/{OWNER}/{REPO}/actions/runs"
export GITHUB_DISPATCH_API="/repos/{OWNER}/{REPO}/dispatches"

# Test result tracking
declare -gA TEST_RESULTS=()
declare -gi TOTAL_TESTS=0
declare -gi PASSED_TESTS=0
declare -gi FAILED_TESTS=0

# Utility functions for test configuration

# Function to validate test environment
validate_test_environment() {
    local errors=0
    
    # Check required environment variables
    if [[ -z "${GITHUB_TOKEN:-}" && -z "${GH_TOKEN:-}" ]]; then
        echo "ERROR: GitHub token not set (GITHUB_TOKEN or GH_TOKEN)" >&2
        errors=$((errors + 1))
    fi
    
    # Check required commands
    local required_commands=("gh" "git" "curl" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "ERROR: Required command not found: $cmd" >&2
            errors=$((errors + 1))
        fi
    done
    
    # Check GitHub authentication
    if ! gh auth status &> /dev/null; then
        echo "ERROR: Not authenticated with GitHub CLI" >&2
        errors=$((errors + 1))
    fi
    
    # Check repository context
    if ! git rev-parse --git-dir &> /dev/null; then
        echo "ERROR: Not in a git repository" >&2
        errors=$((errors + 1))
    fi
    
    return $errors
}

# Function to get repository information
get_repository_info() {
    export GITHUB_OWNER=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
    export GITHUB_REPO=$(basename "$(git rev-parse --show-toplevel)" 2>/dev/null || echo "unknown")
    export GITHUB_REPO_FULL="${GITHUB_OWNER}/${GITHUB_REPO}"
    
    if [[ "$GITHUB_OWNER" == "unknown" || "$GITHUB_REPO" == "unknown" ]]; then
        echo "ERROR: Could not determine repository information" >&2
        return 1
    fi
    
    echo "Repository: $GITHUB_REPO_FULL"
    return 0
}

# Function to generate test kernel version
generate_test_kernel_version() {
    local fedora_version="$1"
    echo "${TEST_KERNEL_VERSIONS[fc${fedora_version}]:-6.11.5-300.fc${fedora_version}.x86_64}"
}

# Function to generate expected package filename
generate_package_filename() {
    local package_type="$1"  # "kmod" or "cli"
    local version="$2"
    local fedora_version="$3"
    local arch="${4:-x86_64}"
    
    case "$package_type" in
        "kmod")
            echo "kmod-maccel-${version}-1.fc${fedora_version}.${arch}.rpm"
            ;;
        "cli")
            echo "maccel-${version}-1.fc${fedora_version}.${arch}.rpm"
            ;;
        *)
            echo "ERROR: Unknown package type: $package_type" >&2
            return 1
            ;;
    esac
}

# Function to generate expected release tag
generate_release_tag() {
    local kernel_version="$1"
    local maccel_version="$2"
    echo "kernel-${kernel_version}-maccel-${maccel_version}"
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
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    # Log result
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] TEST: $test_name - $result${details:+ - $details}"
}

# Function to get test summary
get_test_summary() {
    cat << EOF
=== Test Summary ===
Total Tests: $TOTAL_TESTS
Passed: $PASSED_TESTS
Failed: $FAILED_TESTS
Success Rate: $(( TOTAL_TESTS > 0 ? (PASSED_TESTS * 100) / TOTAL_TESTS : 0 ))%
EOF
}

# Function to wait with progress indicator
wait_with_progress() {
    local duration="$1"
    local message="${2:-Waiting}"
    
    echo -n "$message"
    for ((i=0; i<duration; i++)); do
        sleep 1
        echo -n "."
    done
    echo " done"
}

# Function to retry command with exponential backoff
retry_with_backoff() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local command=("$@")
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if "${command[@]}"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            local wait_time=$((delay * (2 ** (attempt - 1))))
            echo "Attempt $attempt failed, retrying in ${wait_time}s..." >&2
            sleep "$wait_time"
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo "All $max_attempts attempts failed" >&2
    return 1
}

# Function to check GitHub API rate limit
check_github_rate_limit() {
    local rate_info=$(gh api rate_limit --jq '.rate')
    local remaining=$(echo "$rate_info" | jq -r '.remaining')
    local limit=$(echo "$rate_info" | jq -r '.limit')
    local reset_time=$(echo "$rate_info" | jq -r '.reset')
    
    echo "GitHub API Rate Limit: $remaining/$limit remaining"
    
    if [[ $remaining -lt 100 ]]; then
        local reset_date=$(date -d "@$reset_time" '+%Y-%m-%d %H:%M:%S')
        echo "WARNING: Low rate limit remaining. Resets at: $reset_date" >&2
        return 1
    fi
    
    return 0
}

# Function to cleanup test artifacts
cleanup_test_artifacts() {
    local cleanup_age="${1:-60}"  # minutes
    
    echo "Cleaning up test artifacts older than ${cleanup_age} minutes..."
    
    # Clean up temporary files
    find /tmp -name "integration-test-*" -mmin +$cleanup_age -delete 2>/dev/null || true
    find /tmp -name "maccel-build-*" -mmin +$cleanup_age -delete 2>/dev/null || true
    
    # Clean up old log files
    find . -name "*.log" -path "./test-*" -mmin +$cleanup_age -delete 2>/dev/null || true
    
    echo "Cleanup completed"
}

# Function to generate test report
generate_test_report() {
    local report_file="${1:-integration-test-report.json}"
    
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "repository": "${GITHUB_REPO_FULL:-unknown}",
  "test_environment": {
    "timeout": ${INTEGRATION_TEST_TIMEOUT:-3600},
    "workflow_timeout": ${WORKFLOW_TIMEOUT:-1800},
    "poll_interval": ${POLL_INTERVAL:-30},
    "max_retries": ${MAX_RETRIES:-3}
  },
  "summary": {
    "total_tests": ${TOTAL_TESTS:-0},
    "passed_tests": ${PASSED_TESTS:-0},
    "failed_tests": ${FAILED_TESTS:-0},
    "success_rate": $(( TOTAL_TESTS > 0 ? (PASSED_TESTS * 100) / TOTAL_TESTS : 0 ))
  },
  "test_results": {
EOF
    
    # Add individual test results
    local first=true
    for test_name in "${!TEST_RESULTS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        echo -n "    \"$test_name\": \"${TEST_RESULTS[$test_name]}\"" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

  }
}
EOF
    
    echo "Test report generated: $report_file"
}

# Export functions for use in other scripts
export -f validate_test_environment
export -f get_repository_info
export -f generate_test_kernel_version
export -f generate_package_filename
export -f generate_release_tag
export -f record_test_result
export -f get_test_summary
export -f wait_with_progress
export -f retry_with_backoff
export -f check_github_rate_limit
export -f cleanup_test_artifacts
export -f generate_test_report