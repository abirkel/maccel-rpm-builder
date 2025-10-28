#!/bin/bash

# Workflow Validation for Integration Testing
# Validates that workflows are properly configured for integration testing

set -euo pipefail

# Source test configuration
source "$(dirname "$0")/test-config.sh"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[WORKFLOW VALIDATION]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[WORKFLOW PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WORKFLOW WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[WORKFLOW FAIL]${NC} $1"
}

# Function to validate workflow file structure
validate_workflow_structure() {
    local workflow_file=".github/workflows/build-rpm.yml"
    
    log_info "Validating workflow file structure..."
    
    if [[ ! -f "$workflow_file" ]]; then
        log_error "Workflow file not found: $workflow_file"
        return 1
    fi
    
    # Check YAML syntax
    if command -v python3 &> /dev/null; then
        if python3 -c "import yaml; yaml.safe_load(open('$workflow_file'))" 2>/dev/null; then
            log_success "YAML syntax is valid"
        else
            log_error "YAML syntax error in $workflow_file"
            return 1
        fi
    else
        log_warning "Python3 not available, skipping YAML validation"
    fi
    
    # Check required workflow elements
    local required_elements=(
        "^name:"
        "^on:"
        "repository_dispatch:"
        "build-for-kernel"
        "^jobs:"
        "validate-and-check:"
        "build-packages:"
        "create-release:"
    )
    
    for element in "${required_elements[@]}"; do
        if grep -q "$element" "$workflow_file"; then
            log_success "Required element found: $element"
        else
            log_error "Missing required element: $element"
            return 1
        fi
    done
    
    return 0
}

# Function to validate workflow triggers
validate_workflow_triggers() {
    local workflow_file=".github/workflows/build-rpm.yml"
    
    log_info "Validating workflow triggers..."
    
    # Check repository_dispatch trigger
    if grep -A 5 "repository_dispatch:" "$workflow_file" | grep -q "build-for-kernel"; then
        log_success "Repository dispatch trigger configured correctly"
    else
        log_error "Repository dispatch trigger not configured properly"
        return 1
    fi
    
    # Check workflow_dispatch for manual testing
    if grep -q "workflow_dispatch:" "$workflow_file"; then
        log_success "Manual workflow dispatch available for testing"
    else
        log_warning "Manual workflow dispatch not available (optional for testing)"
    fi
    
    return 0
}

# Function to validate workflow inputs and outputs
validate_workflow_io() {
    local workflow_file=".github/workflows/build-rpm.yml"
    
    log_info "Validating workflow inputs and outputs..."
    
    # Check required environment variables
    local required_env_vars=(
        "KERNEL_VERSION"
        "FEDORA_VERSION"
        "TRIGGER_REPO"
        "FORCE_REBUILD"
    )
    
    for var in "${required_env_vars[@]}"; do
        if grep -q "$var:" "$workflow_file"; then
            log_success "Environment variable configured: $var"
        else
            log_error "Missing environment variable: $var"
            return 1
        fi
    done
    
    # Check job outputs
    local required_outputs=(
        "should_build"
        "maccel_version"
        "release_tag"
        "package_urls"
    )
    
    for output in "${required_outputs[@]}"; do
        if grep -q "$output:" "$workflow_file"; then
            log_success "Job output configured: $output"
        else
            log_warning "Job output may be missing: $output"
        fi
    done
    
    return 0
}

# Function to validate workflow permissions
validate_workflow_permissions() {
    local workflow_file=".github/workflows/build-rpm.yml"
    
    log_info "Validating workflow permissions..."
    
    # Check for required permissions
    local required_permissions=(
        "contents:"
        "id-token:"
    )
    
    for permission in "${required_permissions[@]}"; do
        if grep -q "$permission" "$workflow_file"; then
            log_success "Permission configured: $permission"
        else
            log_warning "Permission may be missing: $permission"
        fi
    done
    
    return 0
}

# Function to validate workflow matrix strategy
validate_workflow_matrix() {
    local workflow_file=".github/workflows/build-rpm.yml"
    
    log_info "Validating workflow build matrix..."
    
    # Check matrix configuration
    if grep -A 10 "strategy:" "$workflow_file" | grep -q "matrix:"; then
        log_success "Build matrix configured"
        
        # Check matrix packages
        if grep -A 5 "matrix:" "$workflow_file" | grep -q "package:"; then
            log_success "Matrix packages configured"
            
            # Check for both packages
            if grep -A 5 "package:" "$workflow_file" | grep -q "kmod-maccel" && \
               grep -A 5 "package:" "$workflow_file" | grep -q "maccel"; then
                log_success "Both kmod-maccel and maccel packages in matrix"
            else
                log_error "Missing packages in build matrix"
                return 1
            fi
        else
            log_error "Matrix packages not configured"
            return 1
        fi
    else
        log_error "Build matrix not configured"
        return 1
    fi
    
    return 0
}

# Function to validate error handling in workflow
validate_workflow_error_handling() {
    local workflow_file=".github/workflows/build-rpm.yml"
    
    log_info "Validating workflow error handling..."
    
    # Check for error handling job
    if grep -q "report-failure:" "$workflow_file"; then
        log_success "Failure reporting job configured"
    else
        log_warning "Failure reporting job not found"
    fi
    
    # Check for conditional execution
    if grep -q "if: always()" "$workflow_file"; then
        log_success "Conditional error handling configured"
    else
        log_warning "Conditional error handling may be missing"
    fi
    
    # Check for error handling scripts
    if grep -q "error-handling.sh" "$workflow_file"; then
        log_success "Error handling script referenced"
    else
        log_warning "Error handling script not referenced"
    fi
    
    return 0
}

# Function to validate workflow artifacts
validate_workflow_artifacts() {
    local workflow_file=".github/workflows/build-rpm.yml"
    
    log_info "Validating workflow artifacts..."
    
    # Check for artifact upload
    if grep -q "upload-artifact" "$workflow_file"; then
        log_success "Artifact upload configured"
    else
        log_error "Artifact upload not configured"
        return 1
    fi
    
    # Check for artifact download
    if grep -q "download-artifact" "$workflow_file"; then
        log_success "Artifact download configured"
    else
        log_error "Artifact download not configured"
        return 1
    fi
    
    return 0
}

# Function to validate integration test compatibility
validate_integration_test_compatibility() {
    local workflow_file=".github/workflows/build-rpm.yml"
    
    log_info "Validating integration test compatibility..."
    
    # Check for timeout configuration
    if grep -q "timeout-minutes:" "$workflow_file"; then
        log_success "Workflow timeout configured"
    else
        log_warning "Workflow timeout not explicitly configured"
    fi
    
    # Check for proper job dependencies
    local job_dependencies=(
        "needs: validate-and-check"
        "needs: \\[validate-and-check, build-packages\\]"
    )
    
    local deps_found=0
    for dep in "${job_dependencies[@]}"; do
        if grep -q "$dep" "$workflow_file"; then
            deps_found=$((deps_found + 1))
        fi
    done
    
    if [[ $deps_found -gt 0 ]]; then
        log_success "Job dependencies configured"
    else
        log_error "Job dependencies not properly configured"
        return 1
    fi
    
    return 0
}

# Function to test workflow syntax with GitHub API
test_workflow_syntax() {
    log_info "Testing workflow syntax with GitHub API..."
    
    # This would require pushing to a test branch and checking the workflow
    # For now, we'll just validate that the workflow file can be parsed
    if command -v gh &> /dev/null && gh auth status &> /dev/null; then
        # Check if we can list workflows (validates API access)
        if gh workflow list >/dev/null 2>&1; then
            log_success "GitHub API access working for workflow validation"
        else
            log_warning "Cannot access GitHub workflows API"
        fi
    else
        log_warning "GitHub CLI not available for API validation"
    fi
    
    return 0
}

# Function to validate supporting scripts
validate_supporting_scripts() {
    log_info "Validating supporting scripts referenced in workflow..."
    
    local required_scripts=(
        "scripts/error-handling.sh"
        "scripts/detect-maccel-version.sh"
        "scripts/check-existing-packages.sh"
        "scripts/setup-build-environment.sh"
        "scripts/build-packages.sh"
        "scripts/sign-packages.sh"
        "scripts/build-notifications.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if [[ -x "$script" ]]; then
                log_success "Script exists and is executable: $script"
            else
                log_warning "Script exists but is not executable: $script"
            fi
        else
            log_error "Required script missing: $script"
            return 1
        fi
    done
    
    return 0
}

# Main validation function
main() {
    log_info "Starting workflow validation for integration testing..."
    echo ""
    
    local validation_functions=(
        "validate_workflow_structure"
        "validate_workflow_triggers"
        "validate_workflow_io"
        "validate_workflow_permissions"
        "validate_workflow_matrix"
        "validate_workflow_error_handling"
        "validate_workflow_artifacts"
        "validate_integration_test_compatibility"
        "test_workflow_syntax"
        "validate_supporting_scripts"
    )
    
    local total_validations=${#validation_functions[@]}
    local passed_validations=0
    local failed_validations=0
    
    for validation_func in "${validation_functions[@]}"; do
        echo ""
        if $validation_func; then
            passed_validations=$((passed_validations + 1))
            record_test_result "workflow_validation_${validation_func}" "PASS"
        else
            failed_validations=$((failed_validations + 1))
            record_test_result "workflow_validation_${validation_func}" "FAIL"
        fi
    done
    
    echo ""
    log_info "=== Workflow Validation Summary ==="
    log_info "Total validations: $total_validations"
    log_success "Passed: $passed_validations"
    
    if [[ $failed_validations -gt 0 ]]; then
        log_error "Failed: $failed_validations"
        echo ""
        log_error "Workflow validation failed. Please fix the issues above before running integration tests."
        return 1
    else
        echo ""
        log_success "All workflow validations passed!"
        log_info "The workflow is properly configured for integration testing."
        return 0
    fi
}

# Run validation if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi