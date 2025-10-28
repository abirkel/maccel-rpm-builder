#!/bin/bash
# validate-rpm-specs.sh - Validate RPM spec files with rpmlint
# This script validates both kmod-maccel.spec and maccel.spec files

set -euo pipefail

echo "=== RPM Spec File Validation ==="
echo "Validating RPM specifications with rpmlint..."
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to validate a spec file
validate_spec() {
    local spec_file="$1"
    echo "Validating $spec_file..."
    
    if [ ! -f "$spec_file" ]; then
        echo -e "${RED}ERROR: $spec_file not found${NC}"
        return 1
    fi
    
    # Run rpmlint and capture output
    if rpmlint_output=$(rpmlint "$spec_file" 2>&1); then
        # Check if there are any errors or warnings
        if echo "$rpmlint_output" | grep -q "0 errors, 0 warnings"; then
            echo -e "${GREEN}✓ $spec_file passed validation${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ $spec_file has warnings:${NC}"
            echo "$rpmlint_output"
            return 1
        fi
    else
        echo -e "${RED}✗ $spec_file failed validation:${NC}"
        echo "$rpmlint_output"
        return 1
    fi
}

# Function to check required sections
check_required_sections() {
    local spec_file="$1"
    local required_sections=("Name:" "Version:" "Release:" "Summary:" "License:" "URL:" "Source0:" "%description" "%prep" "%build" "%install" "%files" "%changelog")
    local missing_sections=()
    
    echo "Checking required sections in $spec_file..."
    
    for section in "${required_sections[@]}"; do
        if ! grep -q "^$section" "$spec_file"; then
            missing_sections+=("$section")
        fi
    done
    
    if [ ${#missing_sections[@]} -eq 0 ]; then
        echo -e "${GREEN}✓ All required sections present in $spec_file${NC}"
        return 0
    else
        echo -e "${RED}✗ Missing sections in $spec_file:${NC}"
        printf '%s\n' "${missing_sections[@]}"
        return 1
    fi
}

# Main validation
validation_failed=0

# Validate kmod-maccel.spec
if ! validate_spec "kmod-maccel.spec"; then
    validation_failed=1
fi

if ! check_required_sections "kmod-maccel.spec"; then
    validation_failed=1
fi

echo

# Validate maccel.spec
if ! validate_spec "maccel.spec"; then
    validation_failed=1
fi

if ! check_required_sections "maccel.spec"; then
    validation_failed=1
fi

echo

# Summary
if [ $validation_failed -eq 0 ]; then
    echo -e "${GREEN}=== All RPM spec files passed validation ===${NC}"
    echo "Both kmod-maccel.spec and maccel.spec are compliant with RPM packaging standards."
    exit 0
else
    echo -e "${RED}=== RPM spec validation failed ===${NC}"
    echo "Please fix the issues above before proceeding with package building."
    exit 1
fi