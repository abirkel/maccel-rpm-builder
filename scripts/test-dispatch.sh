#!/bin/bash

# Test Repository Dispatch Script
# This script tests the repository dispatch trigger mechanism

set -euo pipefail

# Default values
KERNEL_VERSION="${1:-6.11.5-300.fc41.x86_64}"
FEDORA_VERSION="${2:-41}"
TRIGGER_REPO="${3:-test-trigger}"
FORCE_REBUILD="${4:-false}"

echo "🧪 Testing repository dispatch trigger"
echo "📋 Parameters:"
echo "   Kernel Version: $KERNEL_VERSION"
echo "   Fedora Version: $FEDORA_VERSION"
echo "   Trigger Repo: $TRIGGER_REPO"
echo "   Force Rebuild: $FORCE_REBUILD"
echo ""

# Check if gh CLI is available and authenticated
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed"
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo "❌ Not authenticated with GitHub. Please run: gh auth login"
    exit 1
fi

# Get repository information
GITHUB_USER=$(gh api user --jq '.login')
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")

echo "🎯 Target repository: $GITHUB_USER/$REPO_NAME"

# Validate kernel version format
if [[ ! "$KERNEL_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.fc[0-9]+\.(x86_64|aarch64)$ ]]; then
    echo "❌ Invalid kernel version format: $KERNEL_VERSION"
    echo "   Expected format: X.Y.Z-REL.fcN.ARCH (e.g., 6.11.5-300.fc41.x86_64)"
    exit 1
fi

# Create payload file
TEMP_PAYLOAD=$(mktemp)
cat > "$TEMP_PAYLOAD" << EOF
{
  "event_type": "build-for-kernel",
  "client_payload": {
    "kernel_version": "$KERNEL_VERSION",
    "fedora_version": "$FEDORA_VERSION",
    "trigger_repo": "$TRIGGER_REPO",
    "force_rebuild": $FORCE_REBUILD
  }
}
EOF

echo "📤 Sending repository dispatch event..."
echo "   Event type: build-for-kernel"
echo "   Payload: $(cat "$TEMP_PAYLOAD")"

# Send repository dispatch
if gh api repos/"$GITHUB_USER"/"$REPO_NAME"/dispatches \
    --method POST \
    --input "$TEMP_PAYLOAD"; then
    
    echo "✅ Repository dispatch sent successfully!"
    echo ""
    echo "🔍 Check workflow status:"
    echo "   https://github.com/$GITHUB_USER/$REPO_NAME/actions"
    echo ""
    echo "⏱️  The workflow should start within a few seconds..."
    
    # Wait a moment and check for recent workflow runs
    sleep 5
    echo "📊 Recent workflow runs:"
    gh run list --limit 3 --repo "$GITHUB_USER/$REPO_NAME" || echo "   (Unable to fetch workflow runs)"
    
else
    rm -f "$TEMP_PAYLOAD"
    echo "❌ Failed to send repository dispatch"
    exit 1
fi