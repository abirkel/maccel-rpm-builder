#!/bin/bash

# Package Building Script for maccel RPM Builder
# This script downloads maccel source and builds RPM packages

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

# Global variables
MACCEL_REPO_URL="https://github.com/Gnarus-G/maccel"
WORK_DIR="/tmp/maccel-build"
RPMBUILD_ROOT="$HOME/rpmbuild"
REPO_ROOT="$(pwd)"  # Save the repository root directory

# Function to clean up work directory
cleanup() {
    if [[ -d "$WORK_DIR" ]]; then
        log_info "Cleaning up work directory: $WORK_DIR"
        rm -rf "$WORK_DIR"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Function to download and prepare maccel source code for Fedora environment
download_maccel_source() {
    local maccel_version="$1"
    local target_commit="${2:-}"
    
    log_info "Downloading maccel source code for Fedora container environment..."
    
    # Clean up any existing work directory
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # Clone the repository
    log_info "Cloning maccel repository..."
    git clone "$MACCEL_REPO_URL" maccel
    cd maccel
    
    # If a specific commit is provided, checkout that commit
    if [[ -n "$target_commit" ]]; then
        log_info "Checking out specific commit: $target_commit"
        git checkout "$target_commit"
    else
        # Try to checkout the version tag if it exists
        if git tag -l | grep -q "^v\?${maccel_version}$"; then
            local tag_name=$(git tag -l | grep "^v\?${maccel_version}$" | head -1)
            log_info "Checking out version tag: $tag_name"
            git checkout "$tag_name"
        else
            log_info "No matching tag found, using main branch"
        fi
    fi
    
    # Verify we have the expected structure for Fedora builds
    if [[ ! -d "driver" || ! -f "driver/Makefile" ]]; then
        log_error "Expected driver directory with Makefile not found"
        return 1
    fi
    
    if [[ ! -f "Cargo.toml" ]]; then
        log_error "Expected workspace Cargo.toml not found"
        return 1
    fi
    
    if [[ ! -d "cli" || ! -f "cli/Cargo.toml" ]]; then
        log_error "Expected cli directory with Cargo.toml not found"
        return 1
    fi
    
    if [[ ! -f "udev_rules/99-maccel.rules" ]]; then
        log_error "Expected udev rules file not found"
        return 1
    fi
    
    # Verify workspace structure for cargo workspace build
    if ! grep -q 'members.*=.*\["cli"' Cargo.toml; then
        log_error "Expected workspace structure not found in Cargo.toml"
        return 1
    fi
    
    # Prepare Fedora-specific build environment
    log_info "Preparing source for Fedora container build environment..."
    
    # Set up cargo environment for Fedora container
    export CARGO_HOME="$(pwd)/.cargo"
    export CC=gcc
    export CXX=g++
    
    # Verify cc build dependency can be handled in Fedora environment
    if grep -q "cc.*=" cli/Cargo.toml || grep -q "cc.*=" Cargo.toml; then
        log_info "Detected cc build dependency - will use Fedora's gcc toolchain"
    fi
    
    log_success "Maccel source code downloaded and prepared for Fedora environment"
    return 0
}

# Function to prepare RPM sources for Fedora container environment
prepare_rpm_sources() {
    local maccel_version="$1"
    local package_name="$2"
    
    log_info "Preparing RPM sources for $package_name in Fedora container environment..."
    
    # Create source tarball with proper structure for Fedora builds
    local source_dir="maccel-${maccel_version}"
    local tarball_name="${source_dir}.tar.gz"
    
    cd "$WORK_DIR"
    
    # Copy source to versioned directory, preserving structure for Fedora builds
    cp -r maccel "$source_dir"
    
    # Ensure proper permissions for Fedora container environment
    find "$source_dir" -type f -name "*.rs" -exec chmod 644 {} \;
    find "$source_dir" -type f -name "Makefile" -exec chmod 644 {} \;
    find "$source_dir" -type f -name "Cargo.toml" -exec chmod 644 {} \;
    find "$source_dir" -type f -name "*.rules" -exec chmod 644 {} \;
    
    # Verify critical files for Fedora builds
    if [[ "$package_name" == "kmod-maccel" ]]; then
        if [[ ! -f "$source_dir/driver/Makefile" ]]; then
            log_error "Kernel module Makefile not found for Fedora build"
            return 1
        fi
        log_info "Verified driver/Makefile for Fedora kernel module build"
    fi
    
    if [[ "$package_name" == "maccel" ]]; then
        if [[ ! -f "$source_dir/Cargo.toml" ]] || [[ ! -f "$source_dir/cli/Cargo.toml" ]]; then
            log_error "Cargo workspace files not found for Fedora Rust build"
            return 1
        fi
        if [[ ! -f "$source_dir/udev_rules/99-maccel.rules" ]]; then
            log_error "Udev rules file not found for Fedora installation"
            return 1
        fi
        log_info "Verified cargo workspace and udev rules for Fedora build"
    fi
    
    # Create tarball
    tar -czf "$tarball_name" "$source_dir"
    
    # Copy tarball to RPM SOURCES directory
    cp "$tarball_name" "$RPMBUILD_ROOT/SOURCES/"
    
    # Copy spec file to RPM SPECS directory
    local spec_file="${package_name}.spec"
    local repo_spec_file="$REPO_ROOT/${spec_file}"
    if [[ -f "$repo_spec_file" ]]; then
        cp "$repo_spec_file" "$RPMBUILD_ROOT/SPECS/"
        log_success "Spec file copied for Fedora build: $spec_file"
    else
        log_error "Spec file not found: $repo_spec_file"
        return 1
    fi
    
    log_success "RPM sources prepared for $package_name in Fedora container environment"
}

# Function to get upstream release notes
get_upstream_release_notes() {
    local version="$1"
    local tag_name="v${version}"
    
    log_info "Fetching upstream release notes for version $version..."
    
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
    local build_date="$3"
    
    # Convert markdown to plain text suitable for RPM changelog
    local formatted_notes=""
    formatted_notes=$(echo "$release_notes" | \
        sed 's/^## /- /g' | \
        sed 's/^### /  - /g' | \
        sed 's/\*\*\([^*]*\)\*\*/\1/g' | \
        sed 's/\[\([^]]*\)\]([^)]*)/\1/g' | \
        sed 's/^* /- /g' | \
        sed '/^$/d' | \
        sed 's/^/  /')
    
    # Create RPM changelog entry
    cat << EOF
* $build_date maccel-rpm-builder - $version-1
- Automated build of maccel $version from upstream repository
- Upstream release notes:
$formatted_notes
EOF
}

# Function to substitute variables in spec file
substitute_spec_variables() {
    local package_name="$1"
    local kernel_version="$2"
    local maccel_version="$3"
    local fedora_version="$4"
    
    log_info "Substituting variables in $package_name spec file..."
    
    local spec_file="$RPMBUILD_ROOT/SPECS/${package_name}.spec"
    
    # Create a temporary file for substitution
    local temp_spec=$(mktemp)
    
    # Get current date for changelog
    local build_date=$(date "+%a %b %d %Y")
    
    # Get upstream release notes and format for RPM
    local changelog_entry=""
    if release_notes=$(get_upstream_release_notes "$maccel_version"); then
        changelog_entry=$(format_release_notes_for_rpm "$maccel_version" "$release_notes" "$build_date")
        log_success "Incorporated upstream release notes into changelog"
    else
        # Fallback changelog entry if no release notes available
        changelog_entry="* $build_date maccel-rpm-builder - $maccel_version-1
- Automated build of maccel $maccel_version from upstream repository
- Built from upstream maccel repository commit"
        log_info "Using fallback changelog entry (no upstream release notes found)"
    fi
    
    # Perform variable substitutions
    sed -e "s/@KERNEL_VERSION@/${kernel_version}/g" \
        -e "s/@MACCEL_VERSION@/${maccel_version}/g" \
        -e "s/@FEDORA_VERSION@/${fedora_version}/g" \
        "$spec_file" > "$temp_spec"
    
    # Replace the changelog section with our generated entry
    # Find the %changelog line and replace everything after it
    awk -v changelog="$changelog_entry" '
        /^%changelog/ { 
            print $0
            print changelog
            next
        }
        /^%changelog/,0 { next }
        { print }
    ' "$temp_spec" > "${temp_spec}.new"
    
    mv "${temp_spec}.new" "$temp_spec"
    
    # Replace original spec file
    mv "$temp_spec" "$spec_file"
    
    log_success "Variables and changelog substituted in $package_name spec file"
}

# Function to build kernel module package using Fedora kernel-devel packages
build_kmod_package() {
    local kernel_version="$1"
    local maccel_version="$2"
    local fedora_version="$3"
    
    log_info "Building kmod-maccel package using Fedora kernel-devel packages..."
    
    # Prepare sources
    prepare_rpm_sources "$maccel_version" "kmod-maccel"
    
    # Substitute variables in spec file
    substitute_spec_variables "kmod-maccel" "$kernel_version" "$maccel_version" "$fedora_version"
    
    # Verify kernel headers are available for the build
    local kernel_headers_dir="/usr/src/kernels"
    if [[ ! -d "$kernel_headers_dir" ]] || [[ -z "$(ls -A $kernel_headers_dir 2>/dev/null)" ]]; then
        log_error "Kernel headers not found in $kernel_headers_dir"
        log_error "Ensure kernel-devel package is installed for kernel version $kernel_version"
        return 1
    fi
    
    log_info "Available kernel headers: $(ls -1 $kernel_headers_dir | tr '\n' ' ')"
    
    # Build the package using Fedora's native kernel build system
    log_info "Running rpmbuild for kmod-maccel with Fedora kernel-devel packages..."
    
    # Set environment variables for kernel module build
    export KDIR="$kernel_headers_dir/$kernel_version"
    if [[ ! -d "$KDIR" ]]; then
        # Try to find the closest matching kernel headers
        local available_kernel=$(ls -1 $kernel_headers_dir | head -1)
        log_warning "Exact kernel headers not found, using: $available_kernel"
        export KDIR="$kernel_headers_dir/$available_kernel"
    fi
    
    if rpmbuild -ba "$RPMBUILD_ROOT/SPECS/kmod-maccel.spec"; then
        log_success "kmod-maccel package built successfully using Fedora kernel-devel"
    else
        log_error "Failed to build kmod-maccel package"
        return 1
    fi
}

# Function to build userspace tools package using Fedora's Rust toolchain
build_maccel_package() {
    local kernel_version="$1"
    local maccel_version="$2"
    local fedora_version="$3"
    
    log_info "Building maccel package using Fedora's native Rust toolchain..."
    
    # Prepare sources
    prepare_rpm_sources "$maccel_version" "maccel"
    
    # Substitute variables in spec file
    substitute_spec_variables "maccel" "$kernel_version" "$maccel_version" "$fedora_version"
    
    # Verify Rust toolchain is available
    if ! command -v rustc >/dev/null 2>&1 || ! command -v cargo >/dev/null 2>&1; then
        log_error "Rust toolchain not found - ensure rust and cargo packages are installed"
        return 1
    fi
    
    log_info "Using Rust toolchain: $(rustc --version)"
    log_info "Using Cargo: $(cargo --version)"
    
    # Verify udev rules file exists for Fedora installation
    local source_dir="$WORK_DIR/maccel"
    if [[ ! -f "$source_dir/udev_rules/99-maccel.rules" ]]; then
        log_error "Udev rules file not found: $source_dir/udev_rules/99-maccel.rules"
        return 1
    fi
    
    # Set up environment for cargo workspace build with cc dependency handling
    export CARGO_HOME="$WORK_DIR/.cargo"
    export CC=gcc
    export CXX=g++
    export PKG_CONFIG_PATH="/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    
    # Build the package using Fedora's Rust toolchain
    log_info "Running rpmbuild for maccel with cargo workspace build..."
    
    if rpmbuild -ba "$RPMBUILD_ROOT/SPECS/maccel.spec"; then
        log_success "maccel package built successfully using Fedora Rust toolchain"
    else
        log_error "Failed to build maccel package"
        return 1
    fi
}

# Function to generate package filenames following Fedora conventions
generate_package_filename() {
    local package_name="$1"
    local version="$2"
    local release="$3"
    local fedora_version="$4"
    local arch="$5"
    
    echo "${package_name}-${version}-${release}.fc${fedora_version}.${arch}.rpm"
}

# Function to copy built packages from Fedora container build
copy_built_packages() {
    local kernel_version="$1"
    local maccel_version="$2"
    local fedora_version="$3"
    local output_dir="${4:-$PWD}"
    
    log_info "Copying built packages from Fedora container build to output directory..."
    
    # Extract architecture from kernel version for Fedora package naming
    local arch="x86_64"  # Default
    if [[ "$kernel_version" =~ \.([^.]+)$ ]]; then
        arch="${BASH_REMATCH[1]}"
    fi
    
    # Define package filenames following Fedora conventions
    local release="1"  # Default release number
    local kmod_filename=$(generate_package_filename "kmod-maccel" "$maccel_version" "$release" "$fedora_version" "$arch")
    local maccel_filename=$(generate_package_filename "maccel" "$maccel_version" "$release" "$fedora_version" "$arch")
    
    # Copy packages from RPM build directory (Fedora-specific paths)
    local rpm_arch_dir="$RPMBUILD_ROOT/RPMS/$arch"
    
    log_info "Looking for packages in: $rpm_arch_dir"
    log_info "Expected kmod package: $kmod_filename"
    log_info "Expected maccel package: $maccel_filename"
    
    # List available packages for debugging
    if [[ -d "$rpm_arch_dir" ]]; then
        log_info "Available packages in $rpm_arch_dir:"
        ls -la "$rpm_arch_dir/" || true
    fi
    
    # Copy kmod-maccel package
    if [[ -f "$rpm_arch_dir/$kmod_filename" ]]; then
        cp "$rpm_arch_dir/$kmod_filename" "$output_dir/"
        log_success "Copied kmod-maccel package: $kmod_filename"
    else
        # Try to find any kmod-maccel package with different naming
        local found_kmod=$(find "$rpm_arch_dir" -name "kmod-maccel-*.rpm" 2>/dev/null | head -1)
        if [[ -n "$found_kmod" ]]; then
            cp "$found_kmod" "$output_dir/"
            kmod_filename=$(basename "$found_kmod")
            log_success "Copied kmod-maccel package (alternative naming): $kmod_filename"
        else
            log_error "kmod-maccel package not found in: $rpm_arch_dir"
            return 1
        fi
    fi
    
    # Copy maccel package
    if [[ -f "$rpm_arch_dir/$maccel_filename" ]]; then
        cp "$rpm_arch_dir/$maccel_filename" "$output_dir/"
        log_success "Copied maccel package: $maccel_filename"
    else
        # Try to find any maccel package with different naming
        local found_maccel=$(find "$rpm_arch_dir" -name "maccel-*.rpm" ! -name "kmod-maccel-*.rpm" 2>/dev/null | head -1)
        if [[ -n "$found_maccel" ]]; then
            cp "$found_maccel" "$output_dir/"
            maccel_filename=$(basename "$found_maccel")
            log_success "Copied maccel package (alternative naming): $maccel_filename"
        else
            log_error "maccel package not found in: $rpm_arch_dir"
            return 1
        fi
    fi
    
    # Generate checksums for Fedora packages
    cd "$output_dir"
    sha256sum *.rpm > checksums.txt
    log_success "Generated checksums file for Fedora packages"
    
    # Get source commit hash for metadata
    local source_commit="unknown"
    if [[ -d "$WORK_DIR/maccel/.git" ]]; then
        cd "$WORK_DIR/maccel"
        source_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        cd "$output_dir"
    fi
    
    # Create build metadata for Fedora container build
    cat > build-info.json << EOF
{
  "kernel_version": "$kernel_version",
  "maccel_version": "$maccel_version",
  "maccel_commit": "$source_commit",
  "fedora_version": "$fedora_version",
  "architecture": "$arch",
  "build_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "build_environment": "fedora-container",
  "packages": [
    {
      "name": "kmod-maccel",
      "filename": "$kmod_filename",
      "type": "kernel-module",
      "description": "Kernel module for maccel mouse acceleration driver (Fedora native build)"
    },
    {
      "name": "maccel",
      "filename": "$maccel_filename",
      "type": "userspace-tools",
      "description": "Userspace CLI tools and configuration for maccel (Fedora Rust build)"
    }
  ]
}
EOF
    
    log_success "Generated build metadata for Fedora container build"
}

# Function to validate built packages
validate_packages() {
    local output_dir="${1:-$PWD}"
    
    log_info "Validating built packages..."
    
    cd "$output_dir"
    
    # Check if packages exist
    local package_count=$(ls -1 *.rpm 2>/dev/null | wc -l)
    if [[ $package_count -eq 0 ]]; then
        log_error "No RPM packages found"
        return 1
    fi
    
    log_info "Found $package_count RPM packages"
    
    # Validate each package
    for rpm_file in *.rpm; do
        log_info "Validating package: $rpm_file"
        
        # Check package integrity
        if rpm -K "$rpm_file" >/dev/null 2>&1; then
            log_success "Package integrity check passed: $rpm_file"
        else
            log_warning "Package integrity check failed: $rpm_file"
        fi
        
        # Query package information
        log_info "Package info for $rpm_file:"
        rpm -qip "$rpm_file" | head -10
    done
    
    log_success "Package validation completed"
}

# Main function
main() {
    local package_type="${1:-}"
    local kernel_version="${2:-}"
    local maccel_version="${3:-}"
    local fedora_version="${4:-}"
    local output_dir="${5:-$PWD}"
    
    if [[ -z "$package_type" || -z "$kernel_version" || -z "$maccel_version" || -z "$fedora_version" ]]; then
        log_error "Usage: $0 <package_type> <kernel_version> <maccel_version> <fedora_version> [output_dir]"
        log_error "Package types: kmod-maccel, maccel, both"
        log_error "Example: $0 both 6.11.5-300.fc41.x86_64 1.0.0 41"
        exit 1
    fi
    
    log_info "Building maccel RPM packages in Fedora container environment"
    log_info "Package type: $package_type"
    log_info "Kernel version: $kernel_version"
    log_info "Maccel version: $maccel_version"
    log_info "Fedora version: $fedora_version"
    log_info "Output directory: $output_dir"
    log_info "Build environment: Native Fedora container with kernel-devel and Rust toolchain"
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Download and prepare source
    if ! download_maccel_source "$maccel_version"; then
        log_error "Failed to download maccel source"
        exit 1
    fi
    
    # Build packages based on type
    case "$package_type" in
        "kmod-maccel")
            build_kmod_package "$kernel_version" "$maccel_version" "$fedora_version"
            ;;
        "maccel")
            build_maccel_package "$kernel_version" "$maccel_version" "$fedora_version"
            ;;
        "both")
            build_kmod_package "$kernel_version" "$maccel_version" "$fedora_version"
            build_maccel_package "$kernel_version" "$maccel_version" "$fedora_version"
            ;;
        *)
            log_error "Unknown package type: $package_type"
            log_error "Valid types: kmod-maccel, maccel, both"
            exit 1
            ;;
    esac
    
    # Copy packages to output directory
    copy_built_packages "$kernel_version" "$maccel_version" "$fedora_version" "$output_dir"
    
    # Validate packages
    validate_packages "$output_dir"
    
    log_success "Package building completed successfully!"
    log_info "Built packages are available in: $output_dir"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi