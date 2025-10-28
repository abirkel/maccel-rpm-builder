#!/bin/bash

# Workflow Validation Script
# This script validates GitHub Actions workflow files

set -euo pipefail

echo "🔍 Validating GitHub Actions workflows..."

WORKFLOW_DIR=".github/workflows"

if [[ ! -d "$WORKFLOW_DIR" ]]; then
    echo "❌ Workflow directory not found: $WORKFLOW_DIR"
    exit 1
fi

# Check if any workflow files exist
WORKFLOW_FILES=("$WORKFLOW_DIR"/*.yml "$WORKFLOW_DIR"/*.yaml)
if [[ ! -e "${WORKFLOW_FILES[0]}" ]]; then
    echo "❌ No workflow files found in $WORKFLOW_DIR"
    exit 1
fi

# Validate each workflow file
for workflow in "$WORKFLOW_DIR"/*.{yml,yaml}; do
    if [[ -f "$workflow" ]]; then
        echo "📋 Validating: $(basename "$workflow")"
        
        # Basic YAML syntax check
        if command -v python3 &> /dev/null; then
            python3 -c "import yaml; yaml.safe_load(open('$workflow'))" 2>/dev/null
            if [[ $? -eq 0 ]]; then
                echo "   ✅ YAML syntax is valid"
            else
                echo "   ❌ YAML syntax error"
                exit 1
            fi
        else
            echo "   ⚠️  Python3 not available, skipping YAML validation"
        fi
        
        # Check for required workflow elements
        if grep -q "^name:" "$workflow"; then
            echo "   ✅ Workflow name defined"
        else
            echo "   ❌ Missing workflow name"
            exit 1
        fi
        
        if grep -q "^on:" "$workflow"; then
            echo "   ✅ Workflow triggers defined"
        else
            echo "   ❌ Missing workflow triggers"
            exit 1
        fi
        
        if grep -q "^jobs:" "$workflow"; then
            echo "   ✅ Jobs section defined"
        else
            echo "   ❌ Missing jobs section"
            exit 1
        fi
        
        echo "   ✅ Basic structure validation passed"
        echo ""
    fi
done

echo "🎉 All workflow files validated successfully!"

# Additional checks for our specific workflows
echo "🔧 Performing additional checks..."

# Check build-rpm.yml for required elements
BUILD_WORKFLOW="$WORKFLOW_DIR/build-rpm.yml"
if [[ -f "$BUILD_WORKFLOW" ]]; then
    echo "📦 Checking build-rpm.yml specifics..."
    
    if grep -q "repository_dispatch:" "$BUILD_WORKFLOW"; then
        echo "   ✅ Repository dispatch trigger configured"
    else
        echo "   ❌ Missing repository dispatch trigger"
        exit 1
    fi
    
    if grep -q "build-for-kernel" "$BUILD_WORKFLOW"; then
        echo "   ✅ Correct event type configured"
    else
        echo "   ❌ Missing build-for-kernel event type"
        exit 1
    fi
    
    if grep -q "matrix:" "$BUILD_WORKFLOW"; then
        echo "   ✅ Build matrix configured"
    else
        echo "   ❌ Missing build matrix"
        exit 1
    fi
fi

echo "✅ All additional checks passed!"