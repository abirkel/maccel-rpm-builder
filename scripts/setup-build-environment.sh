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
    if command_exists apt-get; then
        echo "ubuntu"
    elif command_exists dnf; then
        echo "fedora"
    elif command_exists yum; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

# Function to install RPM build dependencies
install_rpm_dependencies() {
    log_info "Installing RPM build dependencies..."
    
    local os_type=$(detect_os)
    log_info "Detected OS: $os_type"
    
    case "$os_type" in
        "ubuntu")
            # Update package manager
            sudo apt-get update -y
            
            # Install core RPM build tools for Ubuntu
            sudo apt-get install -y \
                rpm \
                rpmlint \
                build-essential \
                make \
                gcc \
                git \
                curl \
                wget \
                alien \
                fakeroot
            
            log_success "RPM build tools installed (Ubuntu)"
            ;;
        "fedora")
            # Update package manager
            sudo dnf update -y
            
            # Install core RPM build tools
            sudo dnf install -y \
                rpm-build \
                rpm-devel \
                rpmlint \
                rpmdevtools \
                make \
                gcc \
                git \
                curl \
                wget
            
            log_success "RPM build tools installed (Fedora)"
            ;;
        "rhel")
            # Update package manager
            sudo yum update -y
            
            # Install core RPM build tools
            sudo yum install -y \
                rpm-build \
                rpm-devel \
                rpmlint \
                rpmdevtools \
                make \
                gcc \
                git \
                curl \
                wget
            
            log_success "RPM build tools installed (RHEL)"
            ;;
        *)
            log_error "Unsupported OS for RPM building: $os_type"
            return 1
            ;;
    esac
}

# Function to install kernel development packages
install_kernel_devel() {
    local kernel_version="$1"
    log_info "Installing kernel development packages for $kernel_version..."
    
    local os_type=$(detect_os)
    
    case "$os_type" in
        "ubuntu")
            # For Ubuntu, we'll install generic kernel headers since we're cross-building
            log_info "Installing generic kernel headers for Ubuntu (cross-building for Fedora)"
            sudo apt-get install -y \
                linux-headers-generic \
                linux-libc-dev
            log_success "Generic kernel development packages installed"
            ;;
        "fedora")
            # Extract base kernel version (remove architecture)
            local base_version=$(echo "$kernel_version" | sed 's/\.[^.]*$//')
            
            # Install kernel-devel for the specific version
            if sudo dnf install -y "kernel-devel-${base_version}"; then
                log_success "Kernel development packages installed for $kernel_version"
            else
                log_warning "Failed to install exact kernel-devel version, trying generic install..."
                sudo dnf install -y kernel-devel
                log_success "Generic kernel-devel installed"
            fi
            ;;
        "rhel")
            # Extract base kernel version (remove architecture)
            local base_version=$(echo "$kernel_version" | sed 's/\.[^.]*$//')
            
            # Install kernel-devel for the specific version
            if sudo yum install -y "kernel-devel-${base_version}"; then
                log_success "Kernel development packages installed for $kernel_version"
            else
                log_warning "Failed to install exact kernel-devel version, trying generic install..."
                sudo yum install -y kernel-devel
                log_success "Generic kernel-devel installed"
            fi
            ;;
        *)
            log_warning "Skipping kernel-devel installation for unsupported OS: $os_type"
            ;;
    esac
}

# Function to install Rust toolchain
install_rust() {
    log_info "Installing Rust toolchain..."
    
    if command_exists rustc; then
        log_info "Rust already installed: $(rustc --version)"
        return 0
    fi
    
    # Install Rust using rustup
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    
    # Source the cargo environment
    source "$HOME/.cargo/env"
    
    # Verify installation
    if command_exists rustc && command_exists cargo; then
        log_success "Rust toolchain installed: $(rustc --version)"
    else
        log_error "Failed to install Rust toolchain"
        return 1
    fi
}

# Function to set up RPM build tree
setup_rpm_build_tree() {
    log_info "Setting up RPM build tree..."
    
    # Create RPM build directories
    rpmdev-setuptree
    
    # Verify directories were created
    local rpm_dirs=("BUILD" "RPMS" "SOURCES" "SPECS" "SRPMS")
    local rpmbuild_root="$HOME/rpmbuild"
    
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
    
    # Check kernel headers
    if [[ ! -d "/usr/src/kernels" ]] || [[ -z "$(ls -A /usr/src/kernels 2>/dev/null)" ]]; then
        log_warning "Kernel headers directory is empty or missing"
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
    install_rust
    
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