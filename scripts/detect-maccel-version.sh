#!/bin/bash

# Maccel Version Detection Script
# This script detects the maccel version using multiple fallback methods

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

# Function to validate semantic version format
validate_version() {
    local version="$1"
    
    # Check if version follows semantic versioning (X.Y.Z or X.Y.Z+suffix)
    if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\+.*)?$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to clean version string (remove 'v' prefix if present)
clean_version() {
    local version="$1"
    echo "$version" | sed 's/^v//'
}

# Method 1: Extract version from Git release tags (preferred)
get_version_from_git_tags() {
    log_info "Attempting to get version from Git release tags..."
    
    local version=""
    
    # Try to get latest release tag using GitHub API
    if command -v gh >/dev/null 2>&1; then
        version=$(gh api repos/Gnarus-G/maccel/releases/latest --jq '.tag_name' 2>/dev/null || true)
    fi
    
    # Fallback to curl if gh is not available
    if [[ -z "$version" ]]; then
        version=$(curl -s https://api.github.com/repos/Gnarus-G/maccel/releases/latest | \
                 jq -r '.tag_name' 2>/dev/null || true)
    fi
    
    if [[ -n "$version" && "$version" != "null" ]]; then
        version=$(clean_version "$version")
        if validate_version "$version"; then
            log_success "Found version from Git tags: $version"
            echo "$version"
            return 0
        else
            log_warning "Invalid version format from Git tags: $version"
        fi
    else
        log_warning "No release tags found or API call failed"
    fi
    
    return 1
}

# Method 2: Parse version from Cargo.toml file (fallback)
get_version_from_cargo_toml() {
    log_info "Attempting to get version from Cargo.toml..."
    
    local version=""
    
    # Try to get version from main Cargo.toml
    version=$(curl -s https://raw.githubusercontent.com/Gnarus-G/maccel/main/Cargo.toml | \
             grep '^version = ' | head -1 | cut -d'"' -f2 2>/dev/null || true)
    
    # If main Cargo.toml doesn't have version, try cli/Cargo.toml
    if [[ -z "$version" ]]; then
        version=$(curl -s https://raw.githubusercontent.com/Gnarus-G/maccel/main/cli/Cargo.toml | \
                 grep '^version = ' | head -1 | cut -d'"' -f2 2>/dev/null || true)
    fi
    
    if [[ -n "$version" ]]; then
        if validate_version "$version"; then
            log_success "Found version from Cargo.toml: $version"
            echo "$version"
            return 0
        else
            log_warning "Invalid version format from Cargo.toml: $version"
        fi
    else
        log_warning "Could not extract version from Cargo.toml"
    fi
    
    return 1
}

# Method 3: Use Git commit hash as fallback
get_version_from_commit_hash() {
    log_info "Using Git commit hash as version fallback..."
    
    local commit_hash=""
    
    # Get latest commit hash from main branch
    commit_hash=$(curl -s https://api.github.com/repos/Gnarus-G/maccel/commits/main | \
                 jq -r '.sha[:7]' 2>/dev/null || true)
    
    if [[ -n "$commit_hash" && "$commit_hash" != "null" ]]; then
        local version="0.0.0+${commit_hash}"
        log_success "Generated version from commit hash: $version"
        echo "$version"
        return 0
    else
        log_error "Failed to get commit hash from GitHub API"
        return 1
    fi
}

# Function to get maccel source commit hash for build tracking
get_source_commit_hash() {
    log_info "Getting maccel source commit hash..."
    local commit_hash=""
    
    # First check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is not installed - required for JSON parsing"
        return 1
    fi
    
    # Get commit hash from GitHub API
    local api_response=""
    api_response=$(curl -s https://api.github.com/repos/Gnarus-G/maccel/commits/main 2>/dev/null || true)
    
    if [[ -z "$api_response" ]]; then
        log_error "Failed to get response from GitHub API"
        return 1
    fi
    
    commit_hash=$(echo "$api_response" | jq -r '.sha' 2>/dev/null || true)
    
    if [[ -n "$commit_hash" && "$commit_hash" != "null" ]]; then
        log_success "Found source commit hash: ${commit_hash:0:8}..."
        echo "$commit_hash"
        return 0
    else
        log_error "Failed to parse commit hash from API response"
        log_info "API response preview: ${api_response:0:200}..."
        return 1
    fi
}

# Function to get release notes for a specific version
get_release_notes() {
    local version="$1"
    local tag_name="v${version}"
    
    log_info "Fetching release notes for version $version..."
    
    # Try to get release notes from GitHub API
    local release_body=""
    release_body=$(curl -s "https://api.github.com/repos/Gnarus-G/maccel/releases/tags/${tag_name}" | \
                  jq -r '.body' 2>/dev/null || true)
    
    # If tag with 'v' prefix doesn't exist, try without 'v'
    if [[ -z "$release_body" || "$release_body" == "null" ]]; then
        tag_name="$version"
        release_body=$(curl -s "https://api.github.com/repos/Gnarus-G/maccel/releases/tags/${tag_name}" | \
                      jq -r '.body' 2>/dev/null || true)
    fi
    
    if [[ -n "$release_body" && "$release_body" != "null" ]]; then
        echo "$release_body"
        return 0
    else
        log_warning "No release notes found for version $version"
        return 1
    fi
}

# Function to format release notes for RPM changelog
format_release_notes_for_rpm() {
    local version="$1"
    local release_notes="$2"
    
    # Convert markdown to plain text suitable for RPM changelog
    # Remove markdown headers, links, and format for RPM
    echo "$release_notes" | \
        sed 's/^## /- /g' | \
        sed 's/^### /  - /g' | \
        sed 's/\*\*\([^*]*\)\*\*/\1/g' | \
        sed 's/\[\([^]]*\)\]([^)]*)/\1/g' | \
        sed 's/^* /- /g' | \
        sed '/^$/d' | \
        sed 's/^/  /'
}

# Main version detection function
detect_maccel_version() {
    log_info "Starting maccel version detection..."
    
    local version=""
    
    # Try methods in order of preference
    if version=$(get_version_from_git_tags); then
        echo "$version"
        return 0
    elif version=$(get_version_from_cargo_toml); then
        echo "$version"
        return 0
    elif version=$(get_version_from_commit_hash); then
        echo "$version"
        return 0
    else
        log_error "All version detection methods failed"
        return 1
    fi
}

# Function to format version for RPM packaging
format_rpm_version() {
    local version="$1"
    
    # Replace '+' with '.' for RPM compatibility (0.0.0+abc123 -> 0.0.0.abc123)
    local rpm_version=$(echo "$version" | sed 's/+/./')
    
    echo "$rpm_version"
}

# Function to display version information
show_version_info() {
    local version="$1"
    local commit_hash="${2:-}"
    
    log_info "=== Maccel Version Information ==="
    log_info "Detected Version: $version"
    log_info "RPM Version: $(format_rpm_version "$version")"
    
    if [[ -n "$commit_hash" ]]; then
        log_info "Source Commit: $commit_hash"
    fi
    
    log_info "================================="
}

# Main function
main() {
    local action="${1:-detect}"
    
    case "$action" in
        "detect")
            if version=$(detect_maccel_version); then
                echo "$version"
                exit 0
            else
                exit 1
            fi
            ;;
        "rpm-format")
            if version=$(detect_maccel_version); then
                format_rpm_version "$version"
                exit 0
            else
                exit 1
            fi
            ;;
        "commit-hash")
            if commit_hash=$(get_source_commit_hash); then
                echo "$commit_hash"
                exit 0
            else
                exit 1
            fi
            ;;
        "info")
            if version=$(detect_maccel_version); then
                commit_hash=$(get_source_commit_hash || echo "")
                show_version_info "$version" "$commit_hash"
                exit 0
            else
                exit 1
            fi
            ;;
        "release-notes")
            if version=$(detect_maccel_version); then
                get_release_notes "$version"
                exit 0
            else
                exit 1
            fi
            ;;
        "rpm-changelog")
            if version=$(detect_maccel_version); then
                if release_notes=$(get_release_notes "$version"); then
                    format_release_notes_for_rpm "$version" "$release_notes"
                    exit 0
                else
                    echo "- Automated build of maccel $version"
                    echo "- Built from upstream maccel repository"
                    exit 0
                fi
            else
                exit 1
            fi
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [action]"
            echo ""
            echo "Actions:"
            echo "  detect        - Detect and output maccel version (default)"
            echo "  rpm-format    - Output version in RPM-compatible format"
            echo "  commit-hash   - Output source commit hash"
            echo "  info          - Display detailed version information"
            echo "  release-notes - Get upstream release notes for detected version"
            echo "  rpm-changelog - Get release notes formatted for RPM changelog"
            echo "  help          - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Detect version"
            echo "  $0 detect             # Same as above"
            echo "  $0 rpm-format         # Get RPM-compatible version"
            echo "  $0 commit-hash        # Get source commit hash"
            echo "  $0 info               # Show detailed information"
            echo "  $0 release-notes      # Get upstream release notes"
            echo "  $0 rpm-changelog      # Get RPM-formatted changelog entry"
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