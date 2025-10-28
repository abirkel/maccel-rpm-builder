#!/bin/bash

# GitHub Repository Setup Script for maccel-rpm-builder
# This script creates the GitHub repository and configures it for RPM building

set -euo pipefail

REPO_NAME="maccel-rpm-builder"
REPO_DESCRIPTION="Automated RPM package builder for maccel mouse acceleration driver"

echo "🚀 Setting up GitHub repository: $REPO_NAME"

# Check if gh CLI is available
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed. Please install it first:"
    echo "   https://cli.github.com/"
    exit 1
fi

# Check if user is authenticated
if ! gh auth status &> /dev/null; then
    echo "❌ Not authenticated with GitHub. Please run: gh auth login"
    exit 1
fi

# Get GitHub username
GITHUB_USER=$(gh api user --jq '.login')
echo "📝 GitHub user: $GITHUB_USER"

# Check if repository already exists
if gh repo view "$GITHUB_USER/$REPO_NAME" &> /dev/null; then
    echo "⚠️  Repository $GITHUB_USER/$REPO_NAME already exists"
    read -p "Do you want to continue with the existing repository? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Aborted"
        exit 1
    fi
else
    # Create GitHub repository
    echo "📦 Creating GitHub repository..."
    gh repo create "$REPO_NAME" \
        --public \
        --description "$REPO_DESCRIPTION" \
        --clone=false
    
    echo "✅ Repository created: https://github.com/$GITHUB_USER/$REPO_NAME"
fi

# Add remote if it doesn't exist
if ! git remote get-url origin &> /dev/null; then
    echo "🔗 Adding GitHub remote..."
    git remote add origin "https://github.com/$GITHUB_USER/$REPO_NAME.git"
else
    echo "🔗 GitHub remote already configured"
fi

# Configure repository settings
echo "⚙️  Configuring repository settings..."

# Enable GitHub Actions
gh api repos/"$GITHUB_USER"/"$REPO_NAME" \
    --method PATCH \
    --field has_issues=true \
    --field has_projects=false \
    --field has_wiki=false \
    --field allow_squash_merge=true \
    --field allow_merge_commit=false \
    --field allow_rebase_merge=false \
    --field delete_branch_on_merge=true

# Set repository topics
gh api repos/"$GITHUB_USER"/"$REPO_NAME"/topics \
    --method PUT \
    --field names='["rpm","packaging","maccel","mouse-acceleration","fedora","blue-build","automation"]'

echo "🏷️  Repository topics configured"

# Configure branch protection (optional, for main branch)
echo "🛡️  Setting up branch protection..."
gh api repos/"$GITHUB_USER"/"$REPO_NAME"/branches/main/protection \
    --method PUT \
    --field required_status_checks='{"strict":false,"contexts":[]}' \
    --field enforce_admins=false \
    --field required_pull_request_reviews=null \
    --field restrictions=null \
    --field allow_force_pushes=false \
    --field allow_deletions=false 2>/dev/null || echo "⚠️  Branch protection setup skipped (branch may not exist yet)"

# Push initial commit if repository is empty
if ! git ls-remote --exit-code origin main &> /dev/null; then
    echo "📤 Pushing initial commit..."
    git add .
    git commit -m "Initial commit: RPM builder setup

- Add GitHub Actions workflow for RPM building
- Configure repository dispatch triggers
- Set up build environment and package creation
- Add documentation and configuration files"
    git push -u origin main
    echo "✅ Initial commit pushed"
else
    echo "📤 Repository already has commits, skipping initial push"
fi

echo ""
echo "🎉 GitHub repository setup complete!"
echo ""
echo "📋 Next steps:"
echo "   1. Review the GitHub Actions workflow at: https://github.com/$GITHUB_USER/$REPO_NAME/actions"
echo "   2. Test the repository dispatch trigger"
echo "   3. Configure any additional repository secrets if needed"
echo ""
echo "🔗 Repository URL: https://github.com/$GITHUB_USER/$REPO_NAME"
echo "📦 Releases will be available at: https://github.com/$GITHUB_USER/$REPO_NAME/releases"