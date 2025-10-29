#!/bin/bash

# Comprehensive Error Handling Library for maccel RPM Builder
# This script provides centralized error handling, validation, and monitoring functions

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Error severity levels
declare -r ERROR_LEVEL_INFO=0
declare -r ERROR_LEVEL_WARNING=1
declare -r ERROR_LEVEL_ERROR=2
declare -r ERROR_LEVEL_CRITICAL=3

# Global error tracking
declare -g ERROR_COUNT=0
declare -g WARNING_COUNT=0
declare -g ERROR_LOG_FILE=""
declare -g BUILD_START_TIME=""
declare -g TIMEOUT_DURATION=3600  # 1 hour default timeout

# Initialize error handling system
init_error_handling() {
    local log_dir="${1:-/tmp}"
    local build_id="${2:-$(date +%Y%m%d_%H%M%S)}"
    
    ERROR_LOG_FILE="${log_dir}/maccel-build-${build_id}.log"
    BUILD_START_TIME=$(date +%s)
    ERROR_COUNT=0
    WARNING_COUNT=0
    
    # Create log file
    mkdir -p "$(dirname "$ERROR_LOG_FILE")"
    touch "$ERROR_LOG_FILE"
    
    # Log initialization
    log_message "$ERROR_LEVEL_INFO" "Error handling initialized" "log_file=$ERROR_LOG_FILE, build_id=$build_id"
    
    # Set up signal handlers for cleanup
    trap 'handle_script_exit $?' EXIT
    trap 'handle_timeout_signal' TERM
}

# Enhanced logging function with structured output
log_message() {
    local level="$1"
    local message="$2"
    local details="${3:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local caller="${BASH_SOURCE[2]:-unknown}:${BASH_LINENO[1]:-0}"
    
    # Determine log level name and color
    local level_name=""
    local color=""
    case "$level" in
        $ERROR_LEVEL_INFO)
            level_name="INFO"
            color="$BLUE"
            ;;
        $ERROR_LEVEL_WARNING)
            level_name="WARN"
            color="$YELLOW"
            ((WARNING_COUNT++))
            ;;
        $ERROR_LEVEL_ERROR)
            level_name="ERROR"
            color="$RED"
            ((ERROR_COUNT++))
            ;;
        $ERROR_LEVEL_CRITICAL)
            level_name="CRITICAL"
            color="$PURPLE"
            ((ERROR_COUNT++))
            ;;
        *)
            level_name="UNKNOWN"
            color="$NC"
            ;;
    esac
    
    # Format message for console
    local console_msg="${color}[${level_name}]${NC} ${message}"
    if [[ -n "$details" ]]; then
        console_msg="${console_msg} (${details})"
    fi
    
    # Format message for log file (structured)
    local log_msg="${timestamp} [${level_name}] ${caller} ${message}"
    if [[ -n "$details" ]]; then
        log_msg="${log_msg} | ${details}"
    fi
    
    # Output to console
    echo -e "$console_msg" >&2
    
    # Output to log file if available
    if [[ -n "$ERROR_LOG_FILE" ]]; then
        echo "$log_msg" >> "$ERROR_LOG_FILE"
    fi
}

# Convenience logging functions
log_info() {
    log_message "$ERROR_LEVEL_INFO" "$1" "${2:-}"
}

log_warning() {
    log_message "$ERROR_LEVEL_WARNING" "$1" "${2:-}"
}

log_error() {
    log_message "$ERROR_LEVEL_ERROR" "$1" "${2:-}"
}

log_critical() {
    log_message "$ERROR_LEVEL_CRITICAL" "$1" "${2:-}"
}

# Kernel version validation with detailed error reporting
validate_kernel_version() {
    local kernel_version="$1"
    
    log_info "Validating kernel version format" "version=$kernel_version"
    
    # Check basic format
    if [[ ! "$kernel_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.fc[0-9]+\.(x86_64|aarch64)$ ]]; then
        log_error "Invalid kernel version format" "version=$kernel_version, expected=X.Y.Z-REL.fcN.ARCH"
        return 1
    fi
    
    # Extract components for validation
    local version_part=$(echo "$kernel_version" | cut -d'-' -f1)
    local release_part=$(echo "$kernel_version" | cut -d'-' -f2 | cut -d'.' -f1)
    local fedora_part=$(echo "$kernel_version" | grep -oP '\.fc\K[0-9]+')
    local arch_part=$(echo "$kernel_version" | grep -oP '\.(x86_64|aarch64)$' | sed 's/\.//')
    
    # Validate version components
    if [[ ! "$version_part" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid kernel version number" "version_part=$version_part"
        return 1
    fi
    
    # Validate Fedora version (reasonable range)
    if [[ "$fedora_part" -lt 35 || "$fedora_part" -gt 50 ]]; then
        log_warning "Unusual Fedora version detected" "fedora_version=$fedora_part, expected_range=35-50"
    fi
    
    # Check if kernel-devel package might be available
    log_info "Checking kernel-devel package availability" "kernel_version=$kernel_version"
    if ! check_kernel_devel_availability "$kernel_version"; then
        log_warning "kernel-devel package may not be available" "kernel_version=$kernel_version"
    fi
    
    log_info "Kernel version validation passed" "version=$kernel_version"
    return 0
}

# Check kernel-devel package availability
check_kernel_devel_availability() {
    local kernel_version="$1"
    local base_version=$(echo "$kernel_version" | sed 's/\.[^.]*$//')
    
    # Check if we're on a system that uses dnf
    if command -v dnf >/dev/null 2>&1; then
        # Try to query package availability (non-blocking)
        if timeout 30 dnf list available "kernel-devel-${base_version}" >/dev/null 2>&1; then
            log_info "kernel-devel package is available" "version=$base_version"
            return 0
        else
            log_warning "kernel-devel package availability check failed" "version=$base_version, timeout=30s"
            return 1
        fi
    else
        # Fallback: assume kernel development packages are available
        log_info "Kernel development packages assumed to be available"
        return 0
    fi
}

# Maccel source access validation with retry logic
validate_maccel_source_access() {
    local max_retries="${1:-3}"
    local retry_delay="${2:-5}"
    
    log_info "Validating maccel source access" "max_retries=$max_retries, retry_delay=${retry_delay}s"
    
    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        log_info "Attempting to access maccel repository" "attempt=$attempt/$max_retries"
        
        # Test GitHub API access
        if timeout 30 curl -s "https://api.github.com/repos/Gnarus-G/maccel" >/dev/null 2>&1; then
            log_info "Maccel repository access successful" "attempt=$attempt"
            return 0
        else
            log_warning "Maccel repository access failed" "attempt=$attempt/$max_retries"
            
            if [[ $attempt -lt $max_retries ]]; then
                log_info "Retrying after delay" "delay=${retry_delay}s"
                sleep "$retry_delay"
            fi
        fi
        
        ((attempt++))
    done
    
    log_error "Failed to access maccel repository after all retries" "max_retries=$max_retries"
    return 1
}

# Build timeout monitoring
start_build_timeout() {
    local timeout_seconds="${1:-$TIMEOUT_DURATION}"
    
    log_info "Starting build timeout monitor" "timeout=${timeout_seconds}s"
    
    # Start background timeout process
    (
        sleep "$timeout_seconds"
        log_critical "Build timeout exceeded" "timeout=${timeout_seconds}s"
        # Send TERM signal to parent process group
        kill -TERM -$$
    ) &
    
    local timeout_pid=$!
    echo "$timeout_pid" > "/tmp/maccel-build-timeout.pid"
    
    log_info "Build timeout monitor started" "pid=$timeout_pid, timeout=${timeout_seconds}s"
}

# Stop build timeout monitoring
stop_build_timeout() {
    local timeout_pid_file="/tmp/maccel-build-timeout.pid"
    
    if [[ -f "$timeout_pid_file" ]]; then
        local timeout_pid=$(cat "$timeout_pid_file")
        if kill -0 "$timeout_pid" 2>/dev/null; then
            kill "$timeout_pid" 2>/dev/null || true
            log_info "Build timeout monitor stopped" "pid=$timeout_pid"
        fi
        rm -f "$timeout_pid_file"
    fi
}

# Handle timeout signal
handle_timeout_signal() {
    log_critical "Build terminated due to timeout" "duration=${TIMEOUT_DURATION}s"
    generate_error_report "TIMEOUT"
    exit 124  # Standard timeout exit code
}

# Enhanced command execution with error handling
execute_with_error_handling() {
    local command="$1"
    local description="${2:-Executing command}"
    local timeout_seconds="${3:-300}"  # 5 minutes default
    local retry_count="${4:-1}"
    
    log_info "$description" "command=$command, timeout=${timeout_seconds}s, retries=$retry_count"
    
    local attempt=1
    while [[ $attempt -le $retry_count ]]; do
        log_info "Executing command" "attempt=$attempt/$retry_count"
        
        # Execute command with timeout
        if timeout "$timeout_seconds" bash -c "$command"; then
            log_info "Command executed successfully" "attempt=$attempt"
            return 0
        else
            local exit_code=$?
            log_error "Command execution failed" "attempt=$attempt/$retry_count, exit_code=$exit_code"
            
            # Handle specific exit codes
            case $exit_code in
                124)
                    log_error "Command timed out" "timeout=${timeout_seconds}s"
                    ;;
                127)
                    log_error "Command not found" "command=$command"
                    ;;
                130)
                    log_error "Command interrupted by user" "signal=SIGINT"
                    ;;
                *)
                    log_error "Command failed with exit code" "exit_code=$exit_code"
                    ;;
            esac
            
            if [[ $attempt -lt $retry_count ]]; then
                local retry_delay=$((attempt * 2))  # Exponential backoff
                log_info "Retrying after delay" "delay=${retry_delay}s"
                sleep "$retry_delay"
            fi
        fi
        
        ((attempt++))
    done
    
    log_error "Command failed after all retries" "retries=$retry_count"
    return 1
}

# Build failure analysis and reporting
analyze_build_failure() {
    local build_log="${1:-}"
    local package_name="${2:-unknown}"
    
    log_info "Analyzing build failure" "package=$package_name, log_file=$build_log"
    
    local failure_reasons=()
    
    if [[ -n "$build_log" && -f "$build_log" ]]; then
        # Common build failure patterns
        if grep -q "No such file or directory" "$build_log"; then
            failure_reasons+=("Missing files or dependencies")
        fi
        
        if grep -q "Permission denied" "$build_log"; then
            failure_reasons+=("Permission issues")
        fi
        
        if grep -q "No space left on device" "$build_log"; then
            failure_reasons+=("Insufficient disk space")
        fi
        
        if grep -q "kernel.*not found" "$build_log"; then
            failure_reasons+=("Kernel headers not available")
        fi
        
        if grep -q "cargo.*failed" "$build_log"; then
            failure_reasons+=("Rust compilation error")
        fi
        
        if grep -q "make.*Error" "$build_log"; then
            failure_reasons+=("Make build error")
        fi
        
        # Extract specific error messages
        local error_lines=$(grep -i "error\|failed\|fatal" "$build_log" | head -5)
        if [[ -n "$error_lines" ]]; then
            log_error "Build error details" "errors=$error_lines"
        fi
    fi
    
    # Report analysis results
    if [[ ${#failure_reasons[@]} -gt 0 ]]; then
        local reasons_str=$(IFS=', '; echo "${failure_reasons[*]}")
        log_error "Build failure analysis completed" "package=$package_name, reasons=$reasons_str"
    else
        log_error "Build failure analysis inconclusive" "package=$package_name"
    fi
    
    # Generate troubleshooting suggestions
    generate_troubleshooting_suggestions "${failure_reasons[@]}"
}

# Generate troubleshooting suggestions
generate_troubleshooting_suggestions() {
    local reasons=("$@")
    
    log_info "Generating troubleshooting suggestions"
    
    for reason in "${reasons[@]}"; do
        case "$reason" in
            "Missing files or dependencies")
                log_info "Suggestion: Check if all build dependencies are installed"
                log_info "Suggestion: Verify source code download completed successfully"
                ;;
            "Permission issues")
                log_info "Suggestion: Check file permissions and ownership"
                log_info "Suggestion: Ensure build user has necessary privileges"
                ;;
            "Insufficient disk space")
                log_info "Suggestion: Free up disk space in build directory"
                log_info "Suggestion: Check available space with 'df -h'"
                ;;
            "Kernel headers not available")
                log_info "Suggestion: Install kernel-devel package for target kernel"
                log_info "Suggestion: Verify kernel version is available in repositories"
                ;;
            "Rust compilation error")
                log_info "Suggestion: Check Rust toolchain installation"
                log_info "Suggestion: Verify Cargo.toml and source code integrity"
                ;;
            "Make build error")
                log_info "Suggestion: Check Makefile and build environment"
                log_info "Suggestion: Verify kernel build system compatibility"
                ;;
        esac
    done
}

# Resource monitoring and validation
check_system_resources() {
    log_info "Checking system resources"
    
    # Check disk space
    local available_space=$(df /tmp | awk 'NR==2 {print $4}')
    local required_space=1048576  # 1GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        log_error "Insufficient disk space" "available=${available_space}KB, required=${required_space}KB"
        return 1
    else
        log_info "Disk space check passed" "available=${available_space}KB"
    fi
    
    # Check memory (if free command is available)
    local available_memory=0
    if command -v free >/dev/null 2>&1; then
        available_memory=$(free | awk 'NR==2{print $7}' 2>/dev/null || echo "0")
    fi
    local required_memory=524288  # 512MB in KB
    
    if [[ $available_memory -lt $required_memory ]]; then
        log_warning "Low available memory" "available=${available_memory}KB, required=${required_memory}KB"
    else
        log_info "Memory check passed" "available=${available_memory}KB"
    fi
    
    # Check CPU load (if uptime command is available)
    local cpu_load=0
    if command -v uptime >/dev/null 2>&1; then
        cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//' 2>/dev/null || echo "0")
    fi
    local cpu_cores=$(nproc 2>/dev/null || echo "1")
    local load_threshold=$(echo "$cpu_cores * 2" | bc 2>/dev/null || echo $((cpu_cores * 2)))
    
    if (( $(echo "$cpu_load > $load_threshold" | bc -l 2>/dev/null || echo 0) )); then
        log_warning "High CPU load detected" "load=$cpu_load, cores=$cpu_cores, threshold=$load_threshold"
    else
        log_info "CPU load check passed" "load=$cpu_load, cores=$cpu_cores"
    fi
    
    return 0
}

# Network connectivity validation
validate_network_connectivity() {
    log_info "Validating network connectivity"
    
    local test_urls=(
        "https://api.github.com"
        "https://github.com"
        "https://raw.githubusercontent.com"
    )
    
    local failed_urls=()
    
    for url in "${test_urls[@]}"; do
        log_info "Testing connectivity" "url=$url"
        
        if timeout 10 curl -s --head "$url" >/dev/null 2>&1; then
            log_info "Connectivity test passed" "url=$url"
        else
            log_warning "Connectivity test failed" "url=$url"
            failed_urls+=("$url")
        fi
    done
    
    if [[ ${#failed_urls[@]} -gt 0 ]]; then
        local failed_str=$(IFS=', '; echo "${failed_urls[*]}")
        log_error "Network connectivity issues detected" "failed_urls=$failed_str"
        return 1
    else
        log_info "All network connectivity tests passed"
        return 0
    fi
}

# Generate comprehensive error report
generate_error_report() {
    local exit_reason="${1:-UNKNOWN}"
    local report_file="${ERROR_LOG_FILE%.log}_report.json"
    
    log_info "Generating error report" "reason=$exit_reason, report_file=$report_file"
    
    local build_duration=0
    if [[ -n "$BUILD_START_TIME" ]]; then
        build_duration=$(($(date +%s) - BUILD_START_TIME))
    fi
    
    # Collect system information
    local system_info=$(cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "exit_reason": "$exit_reason",
  "build_duration_seconds": $build_duration,
  "error_count": $ERROR_COUNT,
  "warning_count": $WARNING_COUNT,
  "system": {
    "os": "$(uname -s)",
    "kernel": "$(uname -r)",
    "architecture": "$(uname -m)",
    "hostname": "$(hostname 2>/dev/null || echo 'unknown')",
    "uptime": "$(uptime 2>/dev/null || echo 'unknown')",
    "disk_usage": $(df -h / | awk 'NR==2 {print "{\"filesystem\":\"" $1 "\",\"size\":\"" $2 "\",\"used\":\"" $3 "\",\"available\":\"" $4 "\",\"use_percent\":\"" $5 "\"}"}'),
    "memory_usage": $(if command -v free >/dev/null 2>&1; then free -h | awk 'NR==2{print "{\"total\":\"" $2 "\",\"used\":\"" $3 "\",\"free\":\"" $4 "\",\"available\":\"" $7 "\"}"}' 2>/dev/null || echo '{}'; else echo '{}'; fi)
  },
  "environment": {
    "kernel_version": "${KERNEL_VERSION:-unknown}",
    "fedora_version": "${FEDORA_VERSION:-unknown}",
    "maccel_version": "${MACCEL_VERSION:-unknown}",
    "github_repository": "${GITHUB_REPOSITORY:-unknown}",
    "github_workflow": "${GITHUB_WORKFLOW:-unknown}",
    "github_run_id": "${GITHUB_RUN_ID:-unknown}"
  }
}
EOF
)
    
    echo "$system_info" > "$report_file"
    
    log_info "Error report generated" "report_file=$report_file"
    
    # Output summary to console
    echo -e "\n${RED}=== BUILD ERROR SUMMARY ===${NC}"
    echo -e "${RED}Exit Reason:${NC} $exit_reason"
    echo -e "${RED}Build Duration:${NC} ${build_duration}s"
    echo -e "${RED}Errors:${NC} $ERROR_COUNT"
    echo -e "${RED}Warnings:${NC} $WARNING_COUNT"
    echo -e "${RED}Log File:${NC} $ERROR_LOG_FILE"
    echo -e "${RED}Report File:${NC} $report_file"
    echo -e "${RED}=========================${NC}\n"
}

# Handle script exit
handle_script_exit() {
    local exit_code="$1"
    
    # Stop timeout monitor
    stop_build_timeout
    
    # Generate report based on exit code
    local exit_reason="SUCCESS"
    if [[ $exit_code -ne 0 ]]; then
        case $exit_code in
            1) exit_reason="GENERAL_ERROR" ;;
            2) exit_reason="VALIDATION_ERROR" ;;
            124) exit_reason="TIMEOUT" ;;
            130) exit_reason="INTERRUPTED" ;;
            *) exit_reason="UNKNOWN_ERROR" ;;
        esac
    fi
    
    # Generate final report
    if [[ $exit_code -ne 0 || $ERROR_COUNT -gt 0 ]]; then
        generate_error_report "$exit_reason"
    else
        log_info "Build completed successfully" "duration=$(($(date +%s) - BUILD_START_TIME))s, warnings=$WARNING_COUNT"
    fi
}

# Validate build dependencies
validate_build_dependencies() {
    log_info "Validating build dependencies"
    
    local required_commands=(
        "rpmbuild:rpm-build"
        "make:make"
        "gcc:gcc"
        "git:git"
        "curl:curl"
        "rustc:rust"
        "cargo:rust"
        "jq:jq"
        "gh:gh"
    )
    
    local missing_deps=()
    
    for dep in "${required_commands[@]}"; do
        local cmd=$(echo "$dep" | cut -d':' -f1)
        local package=$(echo "$dep" | cut -d':' -f2)
        
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Missing required command" "command=$cmd, package=$package"
            missing_deps+=("$package")
        else
            log_info "Dependency check passed" "command=$cmd"
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        local deps_str=$(IFS=', '; echo "${missing_deps[*]}")
        log_error "Missing build dependencies" "packages=$deps_str"
        log_info "Install missing dependencies with: sudo dnf install $deps_str"
        return 1
    else
        log_info "All build dependencies are available"
        return 0
    fi
}

# Main error handling initialization for scripts
setup_error_handling() {
    local script_name="${1:-$(basename "${BASH_SOURCE[1]}")}"
    local log_dir="${2:-/tmp}"
    
    # Initialize error handling system
    init_error_handling "$log_dir" "${script_name}_$(date +%Y%m%d_%H%M%S)"
    
    # Validate system resources
    check_system_resources
    
    # Validate network connectivity
    validate_network_connectivity
    
    # Start timeout monitoring
    start_build_timeout
    
    log_info "Error handling setup completed" "script=$script_name"
}

# Export functions for use in other scripts
export -f log_info log_warning log_error log_critical
export -f validate_kernel_version validate_maccel_source_access
export -f execute_with_error_handling analyze_build_failure
export -f check_system_resources validate_network_connectivity
export -f validate_build_dependencies setup_error_handling