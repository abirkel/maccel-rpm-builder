# maccel-rpm-builder

RPM package builder for the maccel mouse acceleration driver.

## Overview

This repository creates proper RPM packages for the maccel mouse acceleration driver on-demand. It receives kernel version information from Blue Build workflows and produces properly packaged kernel modules and userspace tools.

## Packages

- **kmod-maccel**: Kernel module package containing the compiled maccel.ko for specific kernel versions
- **maccel**: Userspace CLI tools package with configuration files and udev rules

## Usage

This repository is triggered via GitHub repository dispatch from Blue Build workflows. See documentation for integration details.

## Development

This project follows Fedora RPM packaging guidelines and uses GitHub Actions for automated building.