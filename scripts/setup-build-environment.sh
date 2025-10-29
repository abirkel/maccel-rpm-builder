#!/bin/bash

# Build Environment Setup Script for maccel RPM Builder
# This script sets up the build environment for creating RPM packages

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect OS and package manager
detect_os() {
    if command_exists dnf; then
        echo "fedora"
    elif command_exists yum; then
        echo "rhel"
    else
        echo "unknown"
    fi
}



# Function to optimize package installation for Fedora containers
optimize_package_installation() {
    # Optimize dnf for faster package installation in Fedora containers
    echo 'fastestmirror=1' >> /etc/dnf/dnf.conf 2>/dev/null || true
    echo 'max_parallel_downloads=10' >> /etc/dnf/dnf.conf 2>/dev/null || true
    echo 'deltarpm=0' >> /etc/dnf/dnf.conf 2>/dev/null || true
    log_info "Optimized dnf configuration for faster package installation"
}

# Function to install RPM build dependencies in Fedora container
install_rpm_dependencies() {
    log_info "Installing RPM build dependencies in Fedora container..."
    
    # Optimize package installation first
    optimize_package_installation
    
    # Update package manager
    dnf update -y
    
    # Install core RPM build tools and maccel build dependencies
    dnf install -y \
        rpm-build \
        rpmdevtools \
        rpmlint \
        make \
        gcc \
        gcc-c++ \
        git \
        curl \
        wget \
        tar \
        gzip \
        findutils \
        which \
        jq \
        pkg-config \
        elfutils-libelf-devel \
        udev \
        kmod \
        rust \
        cargo
    
    log_success "RPM build tools, Rust, and kernel development packages installed"
}

# Function to install kernel development packages in Fedora container
install_kernel_devel() {
    local kernel_version="$1"
    log_info "Installing kernel development packages for $kernel_version..."
    
    # Extract the kernel version without architecture suffix for package matching
    local base_kernel_version=$(echo "$kernel_version" | sed 's/\.[^.]*$//')
    
    log_info "Attempting to install kernel-devel for version: $base_kernel_version"
    
    # Try to install the exact kernel-devel version
    if dnf install -y "kernel-devel-${base_kernel_version}"; then
        log_success "Installed exact kernel-devel package: kernel-devel-${base_kernel_version}"
    else
        log_warning "Exact kernel-devel version not available, installing generic kernel-devel"
        # Fallback to generic kernel-devel package
        if dnf install -y kernel-devel; then
            log_success "Installed generic kernel-devel package"
        else
            log_error "Failed to install kernel-devel package"
            return 1
        fi
    fi
    
    # Verify kernel headers are available
    if [[ -d "/usr/src/kernels" ]] && [[ -n "$(ls -A /usr/src/kernels 2>/dev/null)" ]]; then
        log_success "Kernel headers available in /usr/src/kernels"
        ls -la /usr/src/kernels/
    else
        log_warning "Kernel headers directory is empty or missing"
    fi
}

# Function to verify Rust toolchain installation in Fedora container
verify_rust_installation() {
    log_info "Verifying Rust toolchain installation..."
    
    if command_exists rustc && command_exists cargo; then
        log_success "Rust already installed: $(rustc --version)"
        log_info "Cargo version: $(cargo --version)"
        return 0
    fi
    
    # Rust should already be installed via dnf in install_rpm_dependencies
    log_warning "Rust not found but should have been installed via dnf"
    log_info "Attempting to install Rust via dnf..."
    if dnf install -y rust cargo; then
        log_success "Rust toolchain installed via dnf: $(rustc --version)"
    else
        log_error "Failed to install Rust via dnf"
        return 1
    fi
}

# Function to set up RPM build tree in Fedora container
setup_rpm_build_tree() {
    log_info "Setting up RPM build tree using native Fedora tools..."
    
    local rpmbuild_root="$HOME/rpmbuild"
    
    # Use rpmdev-setuptree for native Fedora systems
    if command_exists rpmdev-setuptree; then
        rpmdev-setuptree
        log_success "RPM build tree created using rpmdev-setuptree"
    else
        log_warning "rpmdev-setuptree not found, creating directories manually"
        mkdir -p "$rpmbuild_root"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
        mkdir -p "$rpmbuild_root/RPMS"/{i386,i586,i686,x86_64,noarch,aarch64}
        
        # Create .rpmmacros file
        cat > "$HOME/.rpmmacros" << EOF
%_topdir $rpmbuild_root
%_tmppath $rpmbuild_root/tmp
EOF
    fi
    
    # Verify directories were created
    local rpm_dirs=("BUILD" "RPMS" "SOURCES" "SPECS" "SRPMS")
    
    for dir in "${rpm_dirs[@]}"; do
        if [[ ! -d "$rpmbuild_root/$dir" ]]; then
            log_error "Failed to create RPM build directory: $rpmbuild_root/$dir"
            return 1
        fi
    done
    
    log_success "RPM build tree created at $rpmbuild_root"
}

# Function to configure build environment variables
configure_build_environment() {
    local kernel_version="$1"
    local fedora_version="$2"
    local maccel_version="$3"
    
    log_info "Configuring build environment variables..."
    
    # Set up environment variables
    export KERNEL_VERSION="$kernel_version"
    export FEDORA_VERSION="$fedora_version"
    export MACCEL_VERSION="$maccel_version"
    export RPMBUILD_ROOT="$HOME/rpmbuild"
    
    # Extract architecture from kernel version
    if [[ "$kernel_version" =~ \.([^.]+)$ ]]; then
        export ARCH="${BASH_REMATCH[1]}"
    else
        export ARCH="x86_64"  # Default architecture
    fi
    
    # Set RPM build macros
    cat > "$HOME/.rpmmacros" << EOF
%_topdir $RPMBUILD_ROOT
%_tmppath $RPMBUILD_ROOT/tmp
%kernel_version $kernel_version
%maccel_version $maccel_version
%fedora_version $fedora_version
%dist .fc$fedora_version
EOF
    
    log_success "Build environment configured"
    log_info "Kernel Version: $KERNEL_VERSION"
    log_info "Fedora Version: $FEDORA_VERSION"
    log_info "Maccel Version: $MACCEL_VERSION"
    log_info "Architecture: $ARCH"
}

# Function to validate build environment
validate_build_environment() {
    log_info "Validating build environment..."
    
    local errors=0
    
    # Check required commands
    local required_commands=("rpmbuild" "make" "gcc" "git" "curl")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command not found: $cmd"
            ((errors++))
        fi
    done
    
    # Check Rust installation
    if ! command_exists rustc || ! command_exists cargo; then
        log_error "Rust toolchain not properly installed"
        ((errors++))
    fi
    
    # Check RPM build tree
    if [[ ! -d "$HOME/rpmbuild" ]]; then
        log_error "RPM build tree not found"
        ((errors++))
    fi
    
    # Check kernel headers in Fedora container
    if [[ ! -d "/usr/src/kernels" ]] || [[ -z "$(ls -A /usr/src/kernels 2>/dev/null)" ]]; then
        log_warning "Kernel headers directory is empty or missing (/usr/src/kernels)"
    else
        log_info "Kernel headers found: $(ls -1 /usr/src/kernels/ | head -3 | tr '\n' ' ')..."
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Build environment validation passed"
        return 0
    else
        log_error "Build environment validation failed with $errors errors"
        return 1
    fi
}

# Main function
main() {
    local kernel_version="${1:-}"
    local fedora_version="${2:-}"
    local maccel_version="${3:-}"
    
    if [[ -z "$kernel_version" || -z "$fedora_version" || -z "$maccel_version" ]]; then
        log_error "Usage: $0 <kernel_version> <fedora_version> <maccel_version>"
        log_error "Example: $0 6.11.5-300.fc41.x86_64 41 1.0.0"
        exit 1
    fi
    
    log_info "Setting up build environment for maccel RPM packages"
    log_info "Target: Kernel $kernel_version, Fedora $fedora_version, maccel $maccel_version"
    
    # Install dependencies
    install_rpm_dependencies
    install_kernel_devel "$kernel_version"
    verify_rust_installation
    
    # Set up build environment
    setup_rpm_build_tree
    configure_build_environment "$kernel_version" "$fedora_version" "$maccel_version"
    
    # Validate setup
    if validate_build_environment; then
        log_success "Build environment setup completed successfully!"
        log_info "You can now proceed with RPM package building"
    else
        log_error "Build environment setup failed"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi