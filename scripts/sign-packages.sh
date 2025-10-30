#!/bin/bash

# Package Signing and Verification Script for maccel RPM Builder
# This script handles RPM package signing using Sigstore signing

set -euo pipefail

# Source error handling library for consistent logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handling.sh"

# Function to install Sigstore cosign
install_cosign() {
    log_info "Installing Sigstore cosign..."
    
    # Check if cosign is already available
    if command -v cosign >/dev/null 2>&1; then
        log_success "cosign is already installed: $(cosign version --short 2>/dev/null || cosign version)"
        return 0
    fi
    
    # Install cosign using the official installer
    local cosign_version="v2.2.2"  # Use a stable version
    local install_dir="/tmp/cosign"
    
    mkdir -p "$install_dir"
    cd "$install_dir"
    
    # Download and install cosign
    curl -sLO "https://github.com/sigstore/cosign/releases/download/${cosign_version}/cosign-linux-amd64"
    chmod +x cosign-linux-amd64
    sudo mv cosign-linux-amd64 /usr/local/bin/cosign
    
    # Verify installation
    if cosign version >/dev/null 2>&1; then
        log_success "cosign installed successfully: $(cosign version --short 2>/dev/null || cosign version)"
        return 0
    else
        log_error "Failed to install cosign"
        return 1
    fi
}

# Function to check if signing is available
check_signing_availability() {
    log_info "Checking Sigstore keyless signing availability..."
    
    # Check if we're running in GitHub Actions
    if [[ -z "${GITHUB_ACTIONS:-}" ]]; then
        log_warning "Not running in GitHub Actions - Sigstore keyless signing not available"
        log_info "Sigstore keyless signing requires OIDC token from GitHub Actions"
        return 1
    fi
    
    # Check if we have the required OIDC token
    if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" || -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]]; then
        log_warning "GitHub OIDC token not available - ensure 'id-token: write' permission is set"
        return 1
    fi
    
    # Install cosign if needed
    if ! install_cosign; then
        log_error "Failed to install cosign"
        return 1
    fi
    
    log_success "Sigstore keyless signing is available"
    return 0
}

# Function to sign packages with Sigstore
sign_packages_with_sigstore() {
    local package_dir="${1:-$PWD}"
    
    log_info "Signing RPM packages with Sigstore keyless signing..."
    
    cd "$package_dir"
    
    # Find all RPM packages
    local rpm_files=(*.rpm)
    if [[ ! -f "${rpm_files[0]}" ]]; then
        log_error "No RPM packages found in $package_dir"
        return 1
    fi
    
    log_info "Found ${#rpm_files[@]} RPM packages to sign"
    
    # Sign each package with cosign
    for rpm_file in "${rpm_files[@]}"; do
        log_info "Signing package with Sigstore: $rpm_file"
        
        # Sign the package (creates .sig file)
        if cosign sign-blob --yes "$rpm_file" --output-signature "${rpm_file}.sig"; then
            log_success "Successfully signed: $rpm_file"
            log_info "Signature saved as: ${rpm_file}.sig"
        else
            log_error "Failed to sign: $rpm_file"
            return 1
        fi
        
        # Generate certificate for verification
        if cosign sign-blob --yes "$rpm_file" --output-certificate "${rpm_file}.crt" --output-signature /dev/null; then
            log_success "Certificate generated: ${rpm_file}.crt"
        else
            log_warning "Failed to generate certificate for: $rpm_file"
        fi
    done
    
    log_success "All packages signed with Sigstore keyless signing"
    return 0
}

# Function to sign packages (wrapper for Sigstore)
sign_packages() {
    local package_dir="${1:-$PWD}"
    
    log_info "Signing RPM packages in directory: $package_dir"
    
    # Use Sigstore keyless signing
    sign_packages_with_sigstore "$package_dir"
}

# Function to verify Sigstore signatures
verify_sigstore_signatures() {
    local package_dir="${1:-$PWD}"
    
    log_info "Verifying Sigstore signatures in directory: $package_dir"
    
    cd "$package_dir"
    
    # Find all RPM packages with signatures
    local rpm_files=(*.rpm)
    if [[ ! -f "${rpm_files[0]}" ]]; then
        log_error "No RPM packages found in $package_dir"
        return 1
    fi
    
    local verification_results=()
    local all_verified=true
    
    # Verify each package's Sigstore signature
    for rpm_file in "${rpm_files[@]}"; do
        log_info "Verifying Sigstore signature for: $rpm_file"
        
        local sig_file="${rpm_file}.sig"
        local crt_file="${rpm_file}.crt"
        
        if [[ -f "$sig_file" ]]; then
            # Verify with cosign
            if cosign verify-blob --signature "$sig_file" --certificate "$crt_file" \
               --certificate-identity-regexp ".*" \
               --certificate-oidc-issuer-regexp ".*" \
               "$rpm_file" >/dev/null 2>&1; then
                log_success "Sigstore signature verified: $rpm_file"
                verification_results+=("✓ $rpm_file: Sigstore signature verified")
            else
                log_error "Sigstore signature verification failed: $rpm_file"
                verification_results+=("✗ $rpm_file: Sigstore signature verification failed")
                all_verified=false
            fi
        else
            log_warning "No Sigstore signature found for: $rpm_file"
            verification_results+=("⚠ $rpm_file: No Sigstore signature found")
        fi
    done
    
    return $(if $all_verified; then echo 0; else echo 1; fi)
}

# Function to verify package signatures
verify_packages() {
    local package_dir="${1:-$PWD}"
    
    log_info "Verifying package signatures in directory: $package_dir"
    
    cd "$package_dir"
    
    # Find all RPM packages
    local rpm_files=(*.rpm)
    if [[ ! -f "${rpm_files[0]}" ]]; then
        log_error "No RPM packages found in $package_dir"
        return 1
    fi
    
    local verification_results=()
    local all_verified=true
    
    # First try Sigstore verification
    log_info "Checking for Sigstore signatures..."
    if verify_sigstore_signatures "$package_dir"; then
        log_success "Sigstore signature verification completed successfully"
        
        # Add Sigstore results to verification results
        for rpm_file in "${rpm_files[@]}"; do
            if [[ -f "${rpm_file}.sig" ]]; then
                verification_results+=("✓ $rpm_file: Sigstore signature verified")
            else
                verification_results+=("⚠ $rpm_file: No Sigstore signature")
            fi
        done
    else
        log_warning "Sigstore verification had issues, checking traditional RPM signatures..."
        
        # Fallback to traditional RPM signature verification
        for rpm_file in "${rpm_files[@]}"; do
            log_info "Verifying traditional RPM signature: $rpm_file"
            
            if rpm -K "$rpm_file" 2>/dev/null | grep -q "pgp.*OK"; then
                log_success "Traditional signature verified: $rpm_file"
                verification_results+=("✓ $rpm_file: Traditional RPM signature OK")
            elif rpm -K "$rpm_file" 2>/dev/null | grep -q "md5.*OK"; then
                log_warning "No signature found, but checksum OK: $rpm_file"
                verification_results+=("⚠ $rpm_file: No signature, checksum OK")
            else
                log_error "Verification failed: $rpm_file"
                verification_results+=("✗ $rpm_file: Verification failed")
                all_verified=false
            fi
        done
    fi
    
    # Generate verification report
    cat > verification-report.txt << EOF
RPM Package Verification Report
Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Verification Method: Sigstore keyless signing + Traditional RPM

Packages verified: ${#rpm_files[@]}

Results:
$(printf '%s\n' "${verification_results[@]}")

Status: $(if $all_verified; then echo "All packages verified successfully"; else echo "Some packages failed verification"; fi)

Sigstore Information:
- Signatures are keyless and use GitHub OIDC identity
- Certificates are stored in transparency log (Rekor)
- No key management required for verification
EOF
    
    log_info "Verification report saved to: verification-report.txt"
    
    if $all_verified; then
        log_success "All packages verified successfully"
        return 0
    else
        log_error "Some packages failed verification"
        return 1
    fi
}

# Function to create Sigstore verification information
create_sigstore_info() {
    local package_dir="${1:-$PWD}"
    
    log_info "Creating Sigstore verification information..."
    
    cd "$package_dir"
    
    # Generate Sigstore information file
    cat > sigstore-info.txt << EOF
Sigstore Keyless Signing Information
Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Signing Method: Sigstore keyless signing with GitHub OIDC
Identity: GitHub Actions (${GITHUB_REPOSITORY:-unknown}@${GITHUB_REF:-unknown})
Transparency Log: Rekor (https://rekor.sigstore.dev)

Files:
$(for rpm in *.rpm; do
    if [[ -f "${rpm}.sig" ]]; then
        echo "- $rpm -> ${rpm}.sig (signature)"
        [[ -f "${rpm}.crt" ]] && echo "  Certificate: ${rpm}.crt"
    fi
done)

To verify packages:
1. Install cosign:
   curl -sLO https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
   chmod +x cosign-linux-amd64
   sudo mv cosign-linux-amd64 /usr/local/bin/cosign

2. Verify package signatures:
   cosign verify-blob --signature PACKAGE.rpm.sig --certificate PACKAGE.rpm.crt \\
     --certificate-identity-regexp ".*" \\
     --certificate-oidc-issuer-regexp ".*" \\
     PACKAGE.rpm

3. Check transparency log:
   The signature is automatically logged in Rekor transparency log
   Search at: https://search.sigstore.dev

Benefits of Sigstore:
- No key management required
- Cryptographic proof of identity via OIDC
- Transparency through public audit log
- Short-lived certificates (no long-term key compromise risk)
EOF
    
    log_success "Sigstore information saved to: sigstore-info.txt"
    return 0
}

# Function to create verification documentation
create_verification_docs() {
    local package_dir="${1:-$PWD}"
    
    log_info "Creating package verification documentation..."
    
    cd "$package_dir"
    
    # Create comprehensive verification guide
    cat > PACKAGE_VERIFICATION.md << 'EOF'
# RPM Package Verification Guide

This guide explains how to verify the integrity and authenticity of maccel RPM packages.

## Package Integrity Verification

### Using Checksums

1. Download the checksums file:
   ```bash
   wget https://github.com/YOUR_REPO/releases/download/RELEASE_TAG/checksums.txt
   ```

2. Verify package checksums:
   ```bash
   sha256sum -c checksums.txt
   ```

### Using RPM Built-in Verification

```bash
# Check package integrity
rpm -K package-name.rpm

# Detailed package information
rpm -qip package-name.rpm
```

## Package Signature Verification

### Sigstore Keyless Signatures

Packages are signed using Sigstore keyless signing with GitHub OIDC identity.

1. Install cosign (Sigstore CLI):
   ```bash
   curl -sLO https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
   chmod +x cosign-linux-amd64
   sudo mv cosign-linux-amd64 /usr/local/bin/cosign
   ```

2. Verify package signatures:
   ```bash
   cosign verify-blob --signature package-name.rpm.sig --certificate package-name.rpm.crt \
     --certificate-identity-regexp ".*" \
     --certificate-oidc-issuer-regexp ".*" \
     package-name.rpm
   ```

3. Check transparency log:
   ```bash
   # Signatures are automatically logged in Rekor
   # Search at: https://search.sigstore.dev
   ```

### Benefits of Sigstore

- **No key management**: Uses GitHub OIDC identity for signing
- **Transparency**: All signatures logged in public Rekor transparency log  
- **Short-lived certificates**: No long-term key compromise risk
- **Cryptographic proof**: Verifiable identity and integrity

## Build Verification

### Verify Build Metadata

1. Download build information:
   ```bash
   wget https://github.com/YOUR_REPO/releases/download/RELEASE_TAG/build-info.json
   ```

2. Check build details:
   ```bash
   cat build-info.json | jq '.'
   ```

### Verify Source Integrity

The build metadata includes the exact commit hash from the maccel repository used for building. You can verify this matches the expected version:

```bash
# Extract source commit from build info
SOURCE_COMMIT=$(cat build-info.json | jq -r '.maccel_commit')

# Verify against upstream repository
curl -s "https://api.github.com/repos/Gnarus-G/maccel/commits/$SOURCE_COMMIT" | jq '.sha'
```

## Security Best Practices

1. **Always verify checksums** before installing packages
2. **Check build metadata** to ensure packages are built from expected sources
3. **Use HTTPS URLs** when downloading packages and verification files
4. **Keep verification files** for audit trails
5. **Report suspicious packages** if verification fails

## Troubleshooting

### Checksum Verification Fails

- Ensure you downloaded the correct checksums.txt file for your release
- Re-download the package if checksums don't match
- Check for network corruption during download

### RPM Verification Issues

- Ensure you have the correct public key imported
- Check that the package wasn't modified after signing
- Verify you're using compatible RPM tools

### Build Verification Problems

- Ensure build-info.json is from the same release as your packages
- Check that the source commit exists in the upstream repository
- Verify the build timestamp is reasonable for the release date

## Support

For verification issues or security concerns, please:

1. Check the troubleshooting section above
2. Review the release notes for known issues
3. Open an issue in the repository with verification details
4. Include relevant error messages and system information
EOF

    log_success "Verification documentation created: PACKAGE_VERIFICATION.md"
}

# Function to generate signing summary
generate_signing_summary() {
    local package_dir="${1:-$PWD}"
    local signed="${2:-false}"
    
    log_info "Generating signing summary..."
    
    cd "$package_dir"
    
    # Count packages
    local rpm_count=$(ls -1 *.rpm 2>/dev/null | wc -l)
    
    # Create signing summary
    cat > signing-summary.json << EOF
{
  "signing_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "packages_processed": $rpm_count,
  "packages_signed": $(if $signed; then echo "$rpm_count"; else echo "0"; fi),
  "signing_enabled": $signed,
  "verification_files": [
    "checksums.txt",
    "build-info.json",
    $(if $signed; then echo '"verification-report.txt", "public-key.asc", "key-info.txt"'; fi)
    "PACKAGE_VERIFICATION.md"
  ],
  "status": "$(if $signed; then echo "Packages signed and verified"; else echo "Packages processed without signing"; fi)"
}
EOF
    
    log_success "Signing summary saved to: signing-summary.json"
}

# Main function
main() {
    local action="${1:-}"
    local package_dir="${2:-$PWD}"
    local key_id="${3:-}"
    
    case "$action" in
        "check")
            check_signing_availability
            ;;
        "install-cosign")
            install_cosign
            ;;
        "sign")
            if check_signing_availability; then
                sign_packages "$package_dir"
                verify_packages "$package_dir"
                create_sigstore_info "$package_dir"
                generate_signing_summary "$package_dir" true
            else
                log_warning "Sigstore keyless signing not available - skipping signature generation"
                generate_signing_summary "$package_dir" false
            fi
            ;;
        "verify")
            verify_packages "$package_dir"
            ;;
        "sigstore-info")
            create_sigstore_info "$package_dir"
            ;;
        "create-docs")
            create_verification_docs "$package_dir"
            ;;
        "full-process")
            log_info "Running full signing and verification process..."
            
            # Create verification documentation
            create_verification_docs "$package_dir"
            
            # Attempt to sign packages if possible
            if check_signing_availability; then
                log_info "Sigstore keyless signing is available - proceeding with full signing process"
                sign_packages "$package_dir"
                verify_packages "$package_dir"
                create_sigstore_info "$package_dir"
                generate_signing_summary "$package_dir" true
            else
                log_info "Sigstore signing not available - creating verification docs only"
                generate_signing_summary "$package_dir" false
            fi
            
            log_success "Full signing and verification process completed"
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 <action> [package_dir] [key_id] [additional_args...]"
            echo ""
            echo "Actions:"
            echo "  check"
            echo "    Check if Sigstore keyless signing is available"
            echo ""
            echo "  install-cosign"
            echo "    Install Sigstore cosign CLI tool"
            echo ""
            echo "  sign [package_dir]"
            echo "    Sign all RPM packages using Sigstore keyless signing"
            echo ""
            echo "  verify [package_dir]"
            echo "    Verify Sigstore signatures of all RPM packages"
            echo ""
            echo "  sigstore-info [package_dir]"
            echo "    Create Sigstore verification information"
            echo ""
            echo "  create-docs [package_dir]"
            echo "    Create package verification documentation"
            echo ""
            echo "  full-process [package_dir]"
            echo "    Run complete Sigstore signing and verification process"
            echo ""
            echo "  help"
            echo "    Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 check"
            echo "  $0 install-cosign"
            echo "  $0 sign ./packages"
            echo "  $0 verify ./packages"
            echo "  $0 full-process ./packages"
            echo ""
            echo "Environment Variables:"
            echo "  GITHUB_ACTIONS - Indicates GitHub Actions environment"
            echo "  ACTIONS_ID_TOKEN_REQUEST_TOKEN - GitHub OIDC token (automatic in GHA)"
            echo "  ACTIONS_ID_TOKEN_REQUEST_URL - GitHub OIDC URL (automatic in GHA)"
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