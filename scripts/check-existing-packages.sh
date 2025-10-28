#!/bin/bash

# Existing Package Detection Script for maccel RPM Builder
# This script checks for existing packages and determines if builds should be skipped

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to check if a GitHub release exists
check_release_exists() {
    local release_tag="$1"
    
    log_info "Checking if release exists: $release_tag"
    
    if gh release view "$release_tag" >/dev/null 2>&1; then
        log_success "Release found: $release_tag"
        return 0
    else
        log_info "Release not found: $release_tag"
        return 1
    fi
}

# Function to get release metadata from GitHub
get_release_metadata() {
    local release_tag="$1"
    
    log_info "Fetching metadata for release: $release_tag"
    
    # Get release information as JSON
    local release_info=""
    release_info=$(gh release view "$release_tag" --json assets,body,createdAt,tagName 2>/dev/null || echo "")
    
    if [[ -n "$release_info" ]]; then
        echo "$release_info"
        return 0
    else
        log_error "Failed to fetch release metadata for: $release_tag"
        return 1
    fi
}

# Function to extract source commit hash from release metadata
get_release_source_commit() {
    local release_tag="$1"
    
    log_info "Extracting source commit from release: $release_tag"
    
    # Try to get build-info.json from release assets
    local build_info=""
    build_info=$(gh release download "$release_tag" --pattern "build-info.json" --output - 2>/dev/null || echo "")
    
    if [[ -n "$build_info" ]]; then
        local commit_hash=""
        commit_hash=$(echo "$build_info" | jq -r '.maccel_commit // .source_commit // empty' 2>/dev/null || echo "")
        
        if [[ -n "$commit_hash" && "$commit_hash" != "null" ]]; then
            log_success "Found source commit in build metadata: $commit_hash"
            echo "$commit_hash"
            return 0
        fi
    fi
    
    # Fallback: try to extract from release body
    local release_body=""
    release_body=$(gh release view "$release_tag" --json body --jq '.body' 2>/dev/null || echo "")
    
    if [[ -n "$release_body" ]]; then
        local commit_hash=""
        commit_hash=$(echo "$release_body" | grep -oP 'Source Commit.*?:\s*\K[a-f0-9]{40}' || echo "")
        
        if [[ -n "$commit_hash" ]]; then
            log_success "Found source commit in release notes: $commit_hash"
            echo "$commit_hash"
            return 0
        fi
    fi
    
    log_warning "Could not extract source commit from release: $release_tag"
    return 1
}

# Function to get current maccel source commit hash
get_current_source_commit() {
    log_info "Getting current maccel source commit hash..."
    
    local commit_hash=""
    commit_hash=$(./scripts/detect-maccel-version.sh commit-hash 2>/dev/null || echo "")
    
    if [[ -n "$commit_hash" ]]; then
        log_success "Current source commit: $commit_hash"
        echo "$commit_hash"
        return 0
    else
        log_error "Failed to get current source commit hash"
        return 1
    fi
}

# Function to compare commit hashes
compare_source_commits() {
    local existing_commit="$1"
    local current_commit="$2"
    
    log_info "Comparing source commits..."
    log_info "Existing: $existing_commit"
    log_info "Current:  $current_commit"
    
    if [[ "$existing_commit" == "$current_commit" ]]; then
        log_success "Source commits match - no rebuild needed"
        return 0
    else
        log_info "Source commits differ - rebuild required"
        return 1
    fi
}

# Function to get package download URLs from release
get_package_urls() {
    local release_tag="$1"
    
    log_info "Getting package download URLs for release: $release_tag"
    
    # Get release assets
    local assets=""
    assets=$(gh release view "$release_tag" --json assets --jq '.assets[] | select(.name | endswith(".rpm")) | {name: .name, url: .browserDownloadUrl}' 2>/dev/null || echo "")
    
    if [[ -n "$assets" ]]; then
        echo "$assets"
        return 0
    else
        log_error "No RPM packages found in release: $release_tag"
        return 1
    fi
}

# Function to generate release tag name
generate_release_tag() {
    local kernel_version="$1"
    local maccel_version="$2"
    
    echo "kernel-${kernel_version}-maccel-${maccel_version}"
}

# Function to check for existing packages matching kernel version
check_existing_packages() {
    local kernel_version="$1"
    local maccel_version="$2"
    local force_rebuild="${3:-false}"
    
    log_info "Checking for existing packages..."
    log_info "Kernel version: $kernel_version"
    log_info "Maccel version: $maccel_version"
    log_info "Force rebuild: $force_rebuild"
    
    # Generate expected release tag
    local release_tag=""
    release_tag=$(generate_release_tag "$kernel_version" "$maccel_version")
    
    # Check if release exists
    if ! check_release_exists "$release_tag"; then
        log_info "No existing packages found - build required"
        echo "BUILD_REQUIRED"
        return 0
    fi
    
    # If force rebuild is requested, skip further checks
    if [[ "$force_rebuild" == "true" ]]; then
        log_info "Force rebuild requested - will rebuild existing packages"
        echo "BUILD_REQUIRED"
        return 0
    fi
    
    # Get current source commit
    local current_commit=""
    if ! current_commit=$(get_current_source_commit); then
        log_warning "Cannot determine current source commit - will rebuild to be safe"
        echo "BUILD_REQUIRED"
        return 0
    fi
    
    # Get existing release source commit
    local existing_commit=""
    if ! existing_commit=$(get_release_source_commit "$release_tag"); then
        log_warning "Cannot determine existing source commit - will rebuild to be safe"
        echo "BUILD_REQUIRED"
        return 0
    fi
    
    # Compare commits
    if compare_source_commits "$existing_commit" "$current_commit"; then
        log_success "Packages are up-to-date - build can be skipped"
        echo "BUILD_SKIP"
        return 0
    else
        log_info "Source has changed - build required"
        echo "BUILD_REQUIRED"
        return 0
    fi
}

# Function to get existing package information
get_existing_package_info() {
    local kernel_version="$1"
    local maccel_version="$2"
    
    log_info "Getting existing package information..."
    
    # Generate release tag
    local release_tag=""
    release_tag=$(generate_release_tag "$kernel_version" "$maccel_version")
    
    # Check if release exists
    if ! check_release_exists "$release_tag"; then
        log_error "Release does not exist: $release_tag"
        return 1
    fi
    
    # Get package URLs
    local package_urls=""
    if ! package_urls=$(get_package_urls "$release_tag"); then
        log_error "Failed to get package URLs for release: $release_tag"
        return 1
    fi
    
    # Create JSON output with package information
    local repo_url="https://github.com/${GITHUB_REPOSITORY:-$GITHUB_REPOSITORY_OWNER/$GITHUB_REPOSITORY_NAME}"
    local release_url="${repo_url}/releases/tag/${release_tag}"
    
    cat << EOF
{
  "release_tag": "$release_tag",
  "release_url": "$release_url",
  "kernel_version": "$kernel_version",
  "maccel_version": "$maccel_version",
  "packages": $package_urls
}
EOF
    
    return 0
}

# Function to list all releases matching a kernel version pattern
list_kernel_releases() {
    local kernel_version_pattern="$1"
    
    log_info "Listing releases matching kernel pattern: $kernel_version_pattern"
    
    # Get all releases and filter by kernel version pattern
    local releases=""
    releases=$(gh release list --limit 100 --json tagName,createdAt,url | \
              jq --arg pattern "$kernel_version_pattern" \
              '.[] | select(.tagName | startswith("kernel-" + $pattern)) | {tag: .tagName, created: .createdAt, url: .url}' 2>/dev/null || echo "")
    
    if [[ -n "$releases" ]]; then
        echo "$releases"
        return 0
    else
        log_info "No releases found matching pattern: $kernel_version_pattern"
        return 1
    fi
}

# Function to validate inputs
validate_inputs() {
    local kernel_version="$1"
    local maccel_version="${2:-}"
    
    # Validate kernel version format
    if [[ ! "$kernel_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.fc[0-9]+\.(x86_64|aarch64)$ ]]; then
        log_error "Invalid kernel version format: $kernel_version"
        log_error "Expected format: X.Y.Z-REL.fcN.ARCH (e.g., 6.11.5-300.fc41.x86_64)"
        return 1
    fi
    
    # Validate maccel version format if provided
    if [[ -n "$maccel_version" ]]; then
        if [[ ! "$maccel_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\+.*)?$ ]]; then
            log_error "Invalid maccel version format: $maccel_version"
            log_error "Expected format: X.Y.Z or X.Y.Z+suffix"
            return 1
        fi
    fi
    
    return 0
}

# Main function
main() {
    local action="${1:-}"
    local kernel_version="${2:-}"
    local maccel_version="${3:-}"
    local force_rebuild="${4:-false}"
    
    case "$action" in
        "check")
            if [[ -z "$kernel_version" ]]; then
                log_error "Kernel version is required for check action"
                log_error "Usage: $0 check <kernel_version> [maccel_version] [force_rebuild]"
                exit 1
            fi
            
            # Auto-detect maccel version if not provided
            if [[ -z "$maccel_version" ]]; then
                log_info "Auto-detecting maccel version..."
                if ! maccel_version=$(./scripts/detect-maccel-version.sh detect); then
                    log_error "Failed to detect maccel version"
                    exit 1
                fi
                log_info "Detected maccel version: $maccel_version"
            fi
            
            # Validate inputs
            if ! validate_inputs "$kernel_version" "$maccel_version"; then
                exit 1
            fi
            
            # Check for existing packages
            result=$(check_existing_packages "$kernel_version" "$maccel_version" "$force_rebuild")
            echo "$result"
            
            # Set appropriate exit code
            if [[ "$result" == "BUILD_SKIP" ]]; then
                exit 0
            else
                exit 1
            fi
            ;;
        "info")
            if [[ -z "$kernel_version" ]]; then
                log_error "Kernel version is required for info action"
                log_error "Usage: $0 info <kernel_version> [maccel_version]"
                exit 1
            fi
            
            # Auto-detect maccel version if not provided
            if [[ -z "$maccel_version" ]]; then
                if ! maccel_version=$(./scripts/detect-maccel-version.sh detect); then
                    log_error "Failed to detect maccel version"
                    exit 1
                fi
            fi
            
            # Validate inputs
            if ! validate_inputs "$kernel_version" "$maccel_version"; then
                exit 1
            fi
            
            # Get package information
            get_existing_package_info "$kernel_version" "$maccel_version"
            ;;
        "list")
            if [[ -z "$kernel_version" ]]; then
                log_error "Kernel version pattern is required for list action"
                log_error "Usage: $0 list <kernel_version_pattern>"
                exit 1
            fi
            
            # List releases matching kernel version
            list_kernel_releases "$kernel_version"
            ;;
        "release-tag")
            if [[ -z "$kernel_version" ]]; then
                log_error "Kernel version is required for release-tag action"
                log_error "Usage: $0 release-tag <kernel_version> [maccel_version]"
                exit 1
            fi
            
            # Auto-detect maccel version if not provided
            if [[ -z "$maccel_version" ]]; then
                if ! maccel_version=$(./scripts/detect-maccel-version.sh detect); then
                    log_error "Failed to detect maccel version"
                    exit 1
                fi
            fi
            
            # Generate and output release tag
            generate_release_tag "$kernel_version" "$maccel_version"
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 <action> [arguments...]"
            echo ""
            echo "Actions:"
            echo "  check <kernel_version> [maccel_version] [force_rebuild]"
            echo "    Check if packages exist and determine if build is needed"
            echo "    Returns: BUILD_REQUIRED (exit 1) or BUILD_SKIP (exit 0)"
            echo ""
            echo "  info <kernel_version> [maccel_version]"
            echo "    Get information about existing packages (JSON format)"
            echo ""
            echo "  list <kernel_version_pattern>"
            echo "    List all releases matching kernel version pattern"
            echo ""
            echo "  release-tag <kernel_version> [maccel_version]"
            echo "    Generate release tag name for given versions"
            echo ""
            echo "  help"
            echo "    Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 check 6.11.5-300.fc41.x86_64"
            echo "  $0 check 6.11.5-300.fc41.x86_64 1.0.0 true"
            echo "  $0 info 6.11.5-300.fc41.x86_64"
            echo "  $0 list 6.11.5-300.fc41.x86_64"
            echo "  $0 release-tag 6.11.5-300.fc41.x86_64 1.0.0"
            echo ""
            echo "Environment Variables:"
            echo "  GITHUB_REPOSITORY - GitHub repository (owner/name)"
            echo "  GH_TOKEN - GitHub token for API access"
            exit 0
            ;;
        *)
            log_error "Unknown action: $action"
            log_error "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi