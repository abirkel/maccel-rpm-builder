#!/bin/bash

# Build Status Notification System for maccel RPM Builder
# This script provides comprehensive build status reporting and notifications

set -euo pipefail

# Source error handling library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handling.sh"

# Notification types
declare -r NOTIFICATION_SUCCESS="SUCCESS"
declare -r NOTIFICATION_FAILURE="FAILURE"
declare -r NOTIFICATION_WARNING="WARNING"
declare -r NOTIFICATION_INFO="INFO"

# Initialize notification system
init_notification_system() {
    local build_id="${1:-$(date +%Y%m%d_%H%M%S)}"
    local log_dir="${2:-/tmp}"
    
    # Set up error handling if not already initialized
    if [[ -z "${ERROR_LOG_FILE:-}" ]]; then
        init_error_handling "$log_dir" "$build_id"
    fi
    
    log_info "Notification system initialized" "build_id=$build_id"
}

# Generate workflow summary for GitHub Actions
generate_workflow_summary() {
    local status="$1"
    local build_info="$2"
    local package_urls="${3:-}"
    local error_details="${4:-}"
    
    log_info "Generating workflow summary" "status=$status"
    
    local summary_file="${GITHUB_STEP_SUMMARY:-/tmp/workflow-summary.md}"
    
    # Create summary header based on status
    case "$status" in
        "$NOTIFICATION_SUCCESS")
            cat > "$summary_file" << 'EOF'
# ✅ RPM Build Completed Successfully

The maccel RPM packages have been built and published successfully.

EOF
            ;;
        "$NOTIFICATION_FAILURE")
            cat > "$summary_file" << 'EOF'
# ❌ RPM Build Failed

The maccel RPM build process encountered errors and could not complete.

EOF
            ;;
        "$NOTIFICATION_WARNING")
            cat > "$summary_file" << 'EOF'
# ⚠️ RPM Build Completed with Warnings

The maccel RPM packages were built successfully but with some warnings.

EOF
            ;;
        *)
            cat > "$summary_file" << 'EOF'
# 📋 RPM Build Status

Build process status information.

EOF
            ;;
    esac
    
    # Add build information
    if [[ -n "$build_info" ]]; then
        echo "$build_info" >> "$summary_file"
    fi
    
    # Add package URLs for successful builds
    if [[ "$status" == "$NOTIFICATION_SUCCESS" && -n "$package_urls" ]]; then
        cat >> "$summary_file" << 'EOF'

## 📦 Package Downloads

The following RPM packages are now available:

EOF
        echo "$package_urls" >> "$summary_file"
        
        cat >> "$summary_file" << 'EOF'

## 🔧 Installation

### Quick Install
```bash
# Download and install both packages
wget <kmod-maccel-url>
wget <maccel-url>
sudo dnf install ./kmod-maccel-*.rpm ./maccel-*.rpm
```

### Blue Build Integration
Add the package URLs to your Blue Build recipe:
```yaml
rpm:
  install:
    - <kmod-maccel-url>
    - <maccel-url>
```

EOF
    fi
    
    # Add error details for failed builds
    if [[ "$status" == "$NOTIFICATION_FAILURE" && -n "$error_details" ]]; then
        cat >> "$summary_file" << 'EOF'

## 🔍 Error Details

EOF
        echo "$error_details" >> "$summary_file"
        
        cat >> "$summary_file" << 'EOF'

## 🛠️ Troubleshooting

1. **Check the build logs** in the workflow run details
2. **Verify kernel version format** matches: `X.Y.Z-REL.fcN.ARCH`
3. **Ensure maccel repository is accessible** and source code is available
4. **Check system resources** (disk space, memory, network connectivity)
5. **Retry the build** if the error appears to be transient

EOF
    fi
    
    # Add build metadata
    cat >> "$summary_file" << EOF

## 📊 Build Information

- **Build ID**: ${GITHUB_RUN_ID:-unknown}
- **Workflow**: ${GITHUB_WORKFLOW:-unknown}
- **Triggered by**: ${TRIGGER_REPO:-manual}
- **Kernel Version**: ${KERNEL_VERSION:-unknown}
- **Maccel Version**: ${MACCEL_VERSION:-unknown}
- **Fedora Version**: ${FEDORA_VERSION:-unknown}
- **Build Time**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

EOF
    
    # Add error statistics if available
    if [[ -n "${ERROR_COUNT:-}" || -n "${WARNING_COUNT:-}" ]]; then
        cat >> "$summary_file" << EOF
- **Errors**: ${ERROR_COUNT:-0}
- **Warnings**: ${WARNING_COUNT:-0}

EOF
    fi
    
    log_info "Workflow summary generated" "file=$summary_file"
}

# Report build success with download URLs
report_build_success() {
    local release_tag="$1"
    local release_url="$2"
    local package_urls="$3"
    local build_metadata="${4:-}"
    
    log_info "Reporting build success" "release=$release_tag"
    
    # Parse package URLs for display
    local formatted_urls=""
    if [[ -n "$package_urls" ]]; then
        formatted_urls=$(echo "$package_urls" | jq -r '.[] | "- **\(.name)**: [\(.filename)](\(.url))"' 2>/dev/null || echo "Package URLs available in release")
    fi
    
    # Create build information section
    local build_info=$(cat << EOF
## 🎉 Build Successful

The RPM packages have been built and published successfully.

### 📋 Release Information

- **Release Tag**: [\`$release_tag\`]($release_url)
- **Release URL**: $release_url
- **Build Status**: ✅ Success
- **Packages Built**: $(echo "$package_urls" | jq length 2>/dev/null || echo "2") RPM files

EOF
)
    
    # Add build metadata if available
    if [[ -n "$build_metadata" ]]; then
        build_info="${build_info}

### 🔧 Build Details

$(echo "$build_metadata" | jq -r '
"- **Kernel Version**: \(.kernel_version // "unknown")
- **Maccel Version**: \(.maccel_version // "unknown")  
- **Source Commit**: \(.maccel_commit // "unknown")
- **Architecture**: \(.architecture // "unknown")
- **Build Timestamp**: \(.build_timestamp // "unknown")"
' 2>/dev/null || echo "Build metadata available in release")"
    fi
    
    # Generate workflow summary
    generate_workflow_summary "$NOTIFICATION_SUCCESS" "$build_info" "$formatted_urls"
    
    # Log success message
    log_info "Build completed successfully" "release=$release_tag, packages=$(echo "$package_urls" | jq length 2>/dev/null || echo "unknown")"
    
    # Output structured success information
    cat << EOF
{
  "status": "success",
  "release_tag": "$release_tag",
  "release_url": "$release_url",
  "package_count": $(echo "$package_urls" | jq length 2>/dev/null || echo 0),
  "packages": $package_urls,
  "build_metadata": $build_metadata
}
EOF
}

# Report build failure with detailed error information
report_build_failure() {
    local error_type="$1"
    local error_message="$2"
    local error_details="${3:-}"
    local troubleshooting_info="${4:-}"
    
    log_error "Reporting build failure" "type=$error_type, message=$error_message"
    
    # Create error information section
    local error_info=$(cat << EOF
## ❌ Build Failed

The RPM build process encountered an error and could not complete.

### 🚨 Error Information

- **Error Type**: \`$error_type\`
- **Error Message**: $error_message
- **Build Status**: ❌ Failed

EOF
)
    
    # Add detailed error information
    if [[ -n "$error_details" ]]; then
        error_info="${error_info}

### 📋 Error Details

\`\`\`
$error_details
\`\`\`"
    fi
    
    # Add troubleshooting information
    if [[ -n "$troubleshooting_info" ]]; then
        error_info="${error_info}

### 🔧 Troubleshooting Suggestions

$troubleshooting_info"
    fi
    
    # Generate workflow summary
    generate_workflow_summary "$NOTIFICATION_FAILURE" "$error_info" "" "$error_details"
    
    # Log failure message
    log_error "Build failed" "type=$error_type, message=$error_message"
    
    # Output structured failure information
    cat << EOF
{
  "status": "failure",
  "error_type": "$error_type",
  "error_message": "$error_message",
  "error_details": "$error_details",
  "troubleshooting": "$troubleshooting_info",
  "error_count": ${ERROR_COUNT:-0},
  "warning_count": ${WARNING_COUNT:-0}
}
EOF
}

# Report existing packages (build skipped)
report_existing_packages() {
    local release_tag="$1"
    local release_url="$2"
    local package_info="$3"
    
    log_info "Reporting existing packages" "release=$release_tag"
    
    # Parse package information for display
    local formatted_packages=""
    if [[ -n "$package_info" ]]; then
        formatted_packages=$(echo "$package_info" | jq -r '.packages[]? | "- **\(.name)**: [\(.filename)](\(.url))"' 2>/dev/null || echo "Package information available in release")
    fi
    
    # Create information section
    local info_section=$(cat << EOF
## 📦 Packages Already Available

The requested RPM packages already exist and are up-to-date. No build was necessary.

### 📋 Existing Release Information

- **Release Tag**: [\`$release_tag\`]($release_url)
- **Release URL**: $release_url
- **Build Status**: ⏭️ Skipped (packages up-to-date)
- **Available Packages**: $(echo "$package_info" | jq '.packages | length' 2>/dev/null || echo "2") RPM files

EOF
)
    
    # Generate workflow summary
    generate_workflow_summary "$NOTIFICATION_INFO" "$info_section" "$formatted_packages"
    
    # Log info message
    log_info "Build skipped - packages already exist" "release=$release_tag"
    
    # Output structured information
    cat << EOF
{
  "status": "skipped",
  "reason": "packages_exist",
  "release_tag": "$release_tag",
  "release_url": "$release_url",
  "package_info": $package_info
}
EOF
}

# Create detailed error report for debugging
create_error_report() {
    local error_type="$1"
    local build_logs_dir="${2:-./packages}"
    local output_file="${3:-error-report.json}"
    
    log_info "Creating detailed error report" "type=$error_type, output=$output_file"
    
    # Collect build logs
    local build_logs="{}"
    if [[ -d "$build_logs_dir" ]]; then
        # Collect RPM build logs
        if [[ -f "$build_logs_dir/build.log" ]]; then
            local build_log_content=$(tail -100 "$build_logs_dir/build.log" 2>/dev/null | jq -Rs . || echo '""')
            build_logs=$(echo "$build_logs" | jq --argjson content "$build_log_content" '. + {"build_log": $content}')
        fi
        
        # Collect rpmbuild logs
        if [[ -d "$HOME/rpmbuild/BUILD" ]]; then
            local rpmbuild_files=$(find "$HOME/rpmbuild/BUILD" -name "*.log" -type f 2>/dev/null | head -5)
            if [[ -n "$rpmbuild_files" ]]; then
                local rpmbuild_logs="{}"
                while IFS= read -r log_file; do
                    local log_name=$(basename "$log_file")
                    local log_content=$(tail -50 "$log_file" 2>/dev/null | jq -Rs . || echo '""')
                    rpmbuild_logs=$(echo "$rpmbuild_logs" | jq --arg name "$log_name" --argjson content "$log_content" '. + {($name): $content}')
                done <<< "$rpmbuild_files"
                build_logs=$(echo "$build_logs" | jq --argjson rpmbuild "$rpmbuild_logs" '. + {"rpmbuild_logs": $rpmbuild}')
            fi
        fi
    fi
    
    # Collect system information
    local system_info=$(cat << 'EOF'
{
  "disk_usage": {},
  "memory_info": {},
  "process_info": {},
  "network_info": {}
}
EOF
)
    
    # Add disk usage
    if command -v df >/dev/null 2>&1; then
        local disk_info=$(df -h / 2>/dev/null | awk 'NR==2 {print "{\"filesystem\":\"" $1 "\",\"size\":\"" $2 "\",\"used\":\"" $3 "\",\"available\":\"" $4 "\",\"use_percent\":\"" $5 "\"}"}' || echo '{}')
        system_info=$(echo "$system_info" | jq --argjson disk "$disk_info" '.disk_usage = $disk')
    fi
    
    # Add memory information
    if command -v free >/dev/null 2>&1; then
        local memory_info=$(free -h 2>/dev/null | awk 'NR==2{print "{\"total\":\"" $2 "\",\"used\":\"" $3 "\",\"free\":\"" $4 "\",\"available\":\"" $7 "\"}"}' || echo '{}')
        system_info=$(echo "$system_info" | jq --argjson memory "$memory_info" '.memory_info = $memory')
    fi
    
    # Create comprehensive error report
    local error_report=$(cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "error_type": "$error_type",
  "build_environment": {
    "kernel_version": "${KERNEL_VERSION:-unknown}",
    "maccel_version": "${MACCEL_VERSION:-unknown}",
    "fedora_version": "${FEDORA_VERSION:-unknown}",
    "github_repository": "${GITHUB_REPOSITORY:-unknown}",
    "github_workflow": "${GITHUB_WORKFLOW:-unknown}",
    "github_run_id": "${GITHUB_RUN_ID:-unknown}",
    "trigger_repo": "${TRIGGER_REPO:-unknown}"
  },
  "error_statistics": {
    "error_count": ${ERROR_COUNT:-0},
    "warning_count": ${WARNING_COUNT:-0},
    "build_duration": $(($(date +%s) - ${BUILD_START_TIME:-$(date +%s)}))
  },
  "system_info": $system_info,
  "build_logs": $build_logs,
  "error_log_file": "${ERROR_LOG_FILE:-unknown}"
}
EOF
)
    
    # Write error report to file
    echo "$error_report" > "$output_file"
    
    log_info "Error report created" "file=$output_file"
    echo "$error_report"
}

# Send notification to external systems (placeholder for future integrations)
send_external_notification() {
    local notification_type="$1"
    local message="$2"
    local details="${3:-}"
    
    log_info "External notification" "type=$notification_type, message=$message"
    
    # Placeholder for future integrations:
    # - Slack notifications
    # - Discord webhooks
    # - Email notifications
    # - Custom webhook endpoints
    
    # For now, just log the notification
    case "$notification_type" in
        "$NOTIFICATION_SUCCESS")
            log_info "SUCCESS NOTIFICATION: $message" "$details"
            ;;
        "$NOTIFICATION_FAILURE")
            log_error "FAILURE NOTIFICATION: $message" "$details"
            ;;
        "$NOTIFICATION_WARNING")
            log_warning "WARNING NOTIFICATION: $message" "$details"
            ;;
        *)
            log_info "NOTIFICATION: $message" "$details"
            ;;
    esac
}

# Generate build status badge (for README or external display)
generate_status_badge() {
    local status="$1"
    local kernel_version="${2:-unknown}"
    local output_file="${3:-build-status.json}"
    
    local badge_color=""
    local badge_message=""
    
    case "$status" in
        "success")
            badge_color="brightgreen"
            badge_message="build passing"
            ;;
        "failure")
            badge_color="red"
            badge_message="build failing"
            ;;
        "warning")
            badge_color="yellow"
            badge_message="build unstable"
            ;;
        *)
            badge_color="lightgrey"
            badge_message="build unknown"
            ;;
    esac
    
    # Create badge information
    local badge_info=$(cat << EOF
{
  "schemaVersion": 1,
  "label": "maccel-rpm",
  "message": "$badge_message",
  "color": "$badge_color",
  "kernel_version": "$kernel_version",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
    
    echo "$badge_info" > "$output_file"
    log_info "Status badge generated" "status=$status, file=$output_file"
}

# Main notification function
notify_build_status() {
    local action="$1"
    shift
    
    case "$action" in
        "success")
            report_build_success "$@"
            send_external_notification "$NOTIFICATION_SUCCESS" "Build completed successfully" "$1"
            generate_status_badge "success" "${KERNEL_VERSION:-unknown}"
            ;;
        "failure")
            report_build_failure "$@"
            send_external_notification "$NOTIFICATION_FAILURE" "Build failed: $2" "$1"
            generate_status_badge "failure" "${KERNEL_VERSION:-unknown}"
            ;;
        "existing")
            report_existing_packages "$@"
            send_external_notification "$NOTIFICATION_INFO" "Packages already exist" "$1"
            generate_status_badge "success" "${KERNEL_VERSION:-unknown}"
            ;;
        "error-report")
            create_error_report "$@"
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 <action> [arguments...]"
            echo ""
            echo "Actions:"
            echo "  success <release_tag> <release_url> <package_urls> [build_metadata]"
            echo "    Report successful build completion"
            echo ""
            echo "  failure <error_type> <error_message> [error_details] [troubleshooting]"
            echo "    Report build failure with error information"
            echo ""
            echo "  existing <release_tag> <release_url> <package_info>"
            echo "    Report that packages already exist (build skipped)"
            echo ""
            echo "  error-report <error_type> [build_logs_dir] [output_file]"
            echo "    Create detailed error report for debugging"
            echo ""
            echo "Examples:"
            echo "  $0 success kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0 https://... '{...}'"
            echo "  $0 failure VALIDATION_ERROR 'Invalid kernel version' 'Details...'"
            echo "  $0 existing kernel-6.11.5-300.fc41.x86_64-maccel-1.0.0 https://... '{...}'"
            echo "  $0 error-report BUILD_FAILURE ./packages error-report.json"
            exit 0
            ;;
        *)
            log_error "Unknown notification action: $action"
            log_error "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Initialize notification system if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_notification_system "$(basename "$0")_$(date +%Y%m%d_%H%M%S)"
    notify_build_status "$@"
fi