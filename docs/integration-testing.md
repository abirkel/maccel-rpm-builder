# Integration Testing Guide

This document describes the comprehensive integration testing system for the maccel-rpm-builder project.

## Overview

The integration testing system validates the complete end-to-end workflow from repository dispatch triggers to package delivery, ensuring cross-version compatibility and proper error handling.

## Test Architecture

### Test Components

1. **Integration Test Runner** (`scripts/integration-test.sh`)
   - Main integration test orchestrator
   - Tests end-to-end workflows
   - Validates cross-version compatibility
   - Measures performance and caching efficiency

2. **Test Configuration** (`scripts/test-config.sh`)
   - Shared configuration and utilities
   - Test data definitions
   - Common helper functions

3. **Workflow Validation** (`scripts/test-workflow-validation.sh`)
   - Validates GitHub Actions workflow structure
   - Checks workflow triggers and permissions
   - Verifies integration test compatibility

4. **Test Suite Runner** (`scripts/run-integration-tests.sh`)
   - Orchestrates all test suites
   - Provides unified test execution interface
   - Generates comprehensive test reports

### Test Suites

#### 1. Validation Tests (Fast - ~2 minutes)
- Workflow file structure validation
- Script existence and permissions
- Configuration completeness
- GitHub API connectivity

#### 2. Unit Tests (Fast - ~3 minutes)
- Package detection logic
- Version detection mechanisms
- Input validation
- Error handling functions

#### 3. Integration Tests (Moderate - ~30 minutes)
- End-to-end workflow execution
- Repository dispatch triggering
- Package building and release creation
- Download URL validation

#### 4. Cross-Version Compatibility (Slow - ~2 hours)
- Multiple Fedora version testing
- Different kernel version handling
- Package naming consistency
- Dependency resolution

#### 5. Performance Tests (Moderate - ~45 minutes)
- Caching efficiency validation
- Build time measurements
- Resource usage optimization
- Rate limiting compliance

#### 6. Error Handling Tests (Fast - ~10 minutes)
- Invalid input scenarios
- Build failure recovery
- Network error handling
- Timeout management

## Usage

### Quick Start

```bash
# Run basic validation (recommended for regular checks)
./scripts/run-integration-tests.sh validation

# Run quick integration test
./scripts/run-integration-tests.sh integration

# Run full test suite (requires significant time and GitHub Actions minutes)
./scripts/run-integration-tests.sh all --report test-results.json
```

### Test Suite Options

```bash
# Individual test suites
./scripts/run-integration-tests.sh validation      # Fast validation
./scripts/run-integration-tests.sh unit          # Unit tests
./scripts/run-integration-tests.sh integration   # End-to-end tests
./scripts/run-integration-tests.sh compatibility # Cross-version tests
./scripts/run-integration-tests.sh performance   # Performance tests
./scripts/run-integration-tests.sh error-handling # Error scenarios

# Options
./scripts/run-integration-tests.sh --dry-run all  # Show what would run
./scripts/run-integration-tests.sh --verbose unit # Verbose output
./scripts/run-integration-tests.sh --cleanup all  # Clean up before running
```

### Direct Integration Testing

```bash
# Run specific integration test modes
./scripts/integration-test.sh quick          # Single end-to-end test
./scripts/integration-test.sh caching        # Caching efficiency test
./scripts/integration-test.sh cross-version  # Multiple versions
./scripts/integration-test.sh error-handling # Error scenarios
./scripts/integration-test.sh full          # Complete test suite
```

## Prerequisites

### Required Tools
- GitHub CLI (`gh`) - authenticated with appropriate permissions
- Git - repository must be properly configured
- `curl` - for HTTP requests and API calls
- `jq` - for JSON processing
- Python 3 - for YAML validation (optional)

### GitHub Requirements
- Repository with GitHub Actions enabled
- Sufficient GitHub Actions minutes for testing
- Repository dispatch permissions
- Release creation permissions

### Environment Variables
```bash
export GITHUB_TOKEN="your_github_token"  # Required for API access
export TEST_TIMEOUT=3600                 # Optional: override test timeout
export SKIP_CLEANUP=true                 # Optional: skip artifact cleanup
```

## Test Configuration

### Kernel Versions for Testing
The system tests against multiple Fedora versions:
- Fedora 41: `6.11.5-300.fc41.x86_64`
- Fedora 40: `6.10.12-200.fc40.x86_64`
- Fedora 39: `6.8.11-300.fc39.x86_64`

### Test Timeouts
- Individual workflow timeout: 30 minutes
- Full integration test timeout: 1 hour
- Cross-version test timeout: 2 hours

### Rate Limiting
- 60-second delays between major test phases
- GitHub API rate limit monitoring
- Automatic backoff on rate limit hits

## Test Validation

### End-to-End Workflow Validation

1. **Repository Dispatch Trigger**
   - Validates payload format and acceptance
   - Confirms workflow initiation
   - Tracks workflow execution

2. **Build Process Validation**
   - Monitors build job execution
   - Validates package creation
   - Checks build artifacts

3. **Release Creation Validation**
   - Confirms GitHub release creation
   - Validates release assets
   - Checks download URL accessibility

4. **Package Validation**
   - Verifies RPM package integrity
   - Validates package naming conventions
   - Checks metadata completeness

### Cross-Version Compatibility

Tests package building across different:
- Fedora versions (39, 40, 41)
- Kernel versions (corresponding to each Fedora release)
- Architecture targets (x86_64 primary, aarch64 future)

### Performance Metrics

Measures and validates:
- Build time efficiency
- Caching effectiveness
- Resource utilization
- API rate limit compliance

## Troubleshooting

### Common Issues

#### Authentication Failures
```bash
# Check GitHub CLI authentication
gh auth status

# Re-authenticate if needed
gh auth login
```

#### Rate Limit Issues
```bash
# Check current rate limit
gh api rate_limit

# Wait for rate limit reset or use different token
```

#### Workflow Failures
```bash
# Check recent workflow runs
gh run list --limit 5

# View specific workflow logs
gh run view <workflow_id> --log
```

#### Test Environment Issues
```bash
# Validate test environment
./scripts/test-config.sh validate_test_environment

# Clean up test artifacts
./scripts/run-integration-tests.sh --cleanup validation
```

### Debug Information

Test logs are stored in:
- `/tmp/integration-test-*.log` - Integration test logs
- `/tmp/maccel-build-*.log` - Build process logs
- `test-results.json` - Comprehensive test report (if generated)

### Performance Considerations

#### GitHub Actions Minutes
- Full test suite: ~3-4 hours of runner time
- Quick integration test: ~30 minutes
- Validation tests: ~5 minutes

#### API Rate Limits
- GitHub API: 5000 requests/hour (authenticated)
- Repository dispatch: No specific limit
- Releases API: Standard rate limits apply

## Continuous Integration

### Recommended Testing Strategy

1. **Pre-commit**: Run validation tests
2. **Pull requests**: Run unit and integration tests
3. **Main branch**: Run performance tests
4. **Release**: Run full compatibility suite

### Automated Testing Setup

```yaml
# Example GitHub Actions workflow for testing
name: Integration Tests
on:
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 2 * * 0'  # Weekly full test

jobs:
  test:
    runs-on: ubuntu-latest
    container:
      image: fedora:41
    steps:
      - uses: actions/checkout@v4
      - name: Setup Container Environment
        run: |
          dnf update -y
          dnf install -y git curl jq wget
      - name: Run Integration Tests
        run: ./scripts/run-integration-tests.sh integration
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Test Reports

### Report Format
Test reports are generated in JSON format containing:
- Test execution metadata
- Individual test results
- Performance metrics
- Error details and troubleshooting information

### Report Analysis
```bash
# Generate detailed report
./scripts/run-integration-tests.sh all --report detailed-report.json

# View test summary
jq '.summary' detailed-report.json

# View failed tests
jq '.test_results | to_entries | map(select(.value == "FAIL"))' detailed-report.json
```

## Best Practices

### Test Execution
1. Run validation tests before major changes
2. Use dry-run mode to preview test execution
3. Monitor GitHub Actions minutes usage
4. Clean up test artifacts regularly

### Development Workflow
1. Test locally with validation suite
2. Use integration tests for feature validation
3. Run compatibility tests before releases
4. Monitor performance metrics over time

### Maintenance
1. Update test kernel versions quarterly
2. Review and update test timeouts as needed
3. Monitor GitHub API changes affecting tests
4. Keep test documentation current

## Integration with MyAuroraBluebuild

The integration tests validate compatibility with the MyAuroraBluebuild project:

### Tested Integration Points
- Repository dispatch payload format
- Package download URL stability
- Release naming conventions
- Error response handling

### Cross-Project Validation
When integration tests pass, they confirm that:
- MyAuroraBluebuild can successfully trigger builds
- Package URLs remain stable and accessible
- Error handling provides useful feedback
- Performance meets expected standards

This ensures seamless integration between the two projects and validates the complete Blue Build workflow.