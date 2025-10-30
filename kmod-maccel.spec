# kmod-maccel.spec - RPM spec file for maccel kernel module
# This spec file builds the maccel kernel module for a specific kernel version using native Fedora container builds

%define kmod_name maccel
%define kmod_driver_version %{?maccel_version}%{!?maccel_version:1.0.0}
%define kmod_rpm_release %{?rpm_release}%{!?rpm_release:1}
%define kmod_kernel_version %{?kernel_version}%{!?kernel_version:6.11.5-300.fc41.x86_64}

# Extract architecture from kernel version for proper dependency handling
%define kmod_arch %(echo %{kmod_kernel_version} | grep -oP '\\.\\K[^.]+$' || echo "x86_64")

# Clean kernel version without architecture for display purposes
%define kmod_kernel_version_clean %(echo %{kmod_kernel_version} | sed 's/\\.[^.]*$//')

Name:           kmod-%{kmod_name}
Version:        %{kmod_driver_version}
Release:        %{kmod_rpm_release}%{?dist}
Summary:        Kernel module for maccel mouse acceleration driver

License:        GPL-2.0-only
URL:            https://github.com/Gnarus-G/maccel
Source0:        https://github.com/Gnarus-G/maccel/archive/main.tar.gz#/maccel-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root

# Native Fedora kernel development dependencies
BuildRequires:  kernel-devel = %{kmod_kernel_version}
BuildRequires:  kernel-headers = %{kmod_kernel_version}
BuildRequires:  make
BuildRequires:  gcc
BuildRequires:  elfutils-libelf-devel
BuildRequires:  kmod
BuildRequires:  systemd-rpm-macros

# Runtime dependencies for proper Fedora integration
Requires:       kernel = %{kmod_kernel_version}
Requires:       kmod
Provides:       kmod-%{kmod_name} = %{version}-%{release}

# Prevent automatic dependency generation for kernel symbols to avoid conflicts
AutoReqProv:    no

%description
The maccel kernel module provides customizable mouse acceleration similar to
Windows and macOS systems. This package contains the kernel module compiled
for kernel version %{kmod_kernel_version} using Fedora's native kernel build
system and proper Fedora filesystem layout.

%prep
%setup -q -n maccel-%{version}

%build
# Build the kernel module using Fedora's native kernel build system
cd driver

# Use Fedora's kernel build system with proper kernel source directory
make KDIR=/usr/src/kernels/%{kmod_kernel_version} \
     KERNEL_VERSION=%{kmod_kernel_version} \
     V=1

%install
# Create module installation directory using Fedora filesystem layout
install -d %{buildroot}/usr/lib/modules/%{kmod_kernel_version}/extra/%{kmod_name}/

# Install the kernel module with proper permissions
install -m 644 driver/%{kmod_name}.ko %{buildroot}/usr/lib/modules/%{kmod_kernel_version}/extra/%{kmod_name}/

# Create modprobe configuration directory
install -d %{buildroot}/etc/modprobe.d/

# Install modprobe configuration optimized for Fedora's module loading system
cat > %{buildroot}/etc/modprobe.d/%{kmod_name}.conf << EOF
# maccel kernel module configuration for Fedora
# Automatically load maccel module when needed
install %{kmod_name} /usr/sbin/modprobe --ignore-install %{kmod_name}
EOF

# Create modules-load configuration for systemd (Fedora standard)
install -d %{buildroot}%{_modulesloaddir}/
cat > %{buildroot}%{_modulesloaddir}/%{kmod_name}.conf << EOF
# Load maccel kernel module at boot (Fedora systemd integration)
%{kmod_name}
EOF

%files
/usr/lib/modules/%{kmod_kernel_version}/extra/%{kmod_name}/%{kmod_name}.ko
%config(noreplace) /etc/modprobe.d/%{kmod_name}.conf
%{_modulesloaddir}/%{kmod_name}.conf

%post
# Update module dependencies using Fedora's module loading system
/usr/sbin/depmod -a %{kmod_kernel_version} || :

# Reload systemd to recognize new modules-load configuration
/usr/bin/systemctl daemon-reload || :

# Load the module if kernel is running the target version
if [ "$(uname -r)" = "%{kmod_kernel_version}" ]; then
    /usr/sbin/modprobe %{kmod_name} || :
fi

%preun
# Unload module before removal if it's loaded
if /usr/sbin/lsmod | grep -q "^%{kmod_name} "; then
    /usr/sbin/modprobe -r %{kmod_name} || :
fi

%postun
# Update module dependencies after removal using Fedora paths
/usr/sbin/depmod -a %{kmod_kernel_version} || :

# Reload systemd after module removal
/usr/bin/systemctl daemon-reload || :

%check
# Validate that the module was built correctly for Fedora
test -f driver/%{kmod_name}.ko
file driver/%{kmod_name}.ko | grep -q "kernel module"

# Verify module is built for the correct kernel version
/usr/sbin/modinfo driver/%{kmod_name}.ko | grep -q "vermagic:.*%{kmod_kernel_version_clean}" || {
    echo "Warning: Module version magic may not match target kernel exactly"
    /usr/sbin/modinfo driver/%{kmod_name}.ko | grep "vermagic:"
}

%changelog
# Changelog will be generated dynamically during build
* Thu Oct 30 2025 maccel-rpm-builder <noreply@github.com> - 0.0.0-0
- Placeholder entry - actual changelog generated at build time

