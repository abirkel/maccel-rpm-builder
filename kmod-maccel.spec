# kmod-maccel.spec - RPM spec file for maccel kernel module
# This spec file builds the maccel kernel module for a specific kernel version

%define kmod_name maccel
%define kmod_driver_version %{?maccel_version}%{!?maccel_version:1.0.0}
%define kmod_rpm_release %{?rpm_release}%{!?rpm_release:1}
%define kmod_kernel_version %{?kernel_version}%{!?kernel_version:6.11.5-300.fc41.x86_64}

# Strip architecture from kernel version for clean package naming
%define kmod_kernel_version_clean %(echo %{kmod_kernel_version} | sed 's/\\.x86_64$//')

Name:           kmod-%{kmod_name}
Version:        %{kmod_driver_version}
Release:        %{kmod_rpm_release}%{?dist}
Summary:        Kernel module for maccel mouse acceleration driver

License:        GPL-2.0-only
URL:            https://github.com/Gnarus-G/maccel
Source0:        https://github.com/Gnarus-G/maccel/archive/main.tar.gz#/maccel-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root

BuildRequires:  kernel-devel >= %{kmod_kernel_version}
BuildRequires:  kernel-headers >= %{kmod_kernel_version}
BuildRequires:  make
BuildRequires:  gcc
BuildRequires:  elfutils-libelf-devel

Requires:       kernel >= %{kmod_kernel_version}
Provides:       kmod-%{kmod_name} = %{version}-%{release}

# Prevent automatic dependency generation for kernel symbols
AutoReqProv:    no

%description
The maccel kernel module provides customizable mouse acceleration similar to
Windows and macOS systems. This package contains the kernel module compiled
for kernel version %{kmod_kernel_version}.

%prep
%setup -q -n maccel-main

%build
# Build the kernel module using the driver Makefile
cd driver
make KDIR=/lib/modules/%{kmod_kernel_version}/build

%install
# Create module installation directory
install -d %{buildroot}/lib/modules/%{kmod_kernel_version}/extra/%{kmod_name}/

# Install the kernel module
install -m 644 driver/%{kmod_name}.ko %{buildroot}/lib/modules/%{kmod_kernel_version}/extra/%{kmod_name}/

# Create modprobe configuration directory
install -d %{buildroot}/etc/modprobe.d/

# Install modprobe configuration for automatic loading
cat > %{buildroot}/etc/modprobe.d/%{kmod_name}.conf << EOF
# maccel kernel module configuration
# Load maccel module at boot
install %{kmod_name} /sbin/modprobe --ignore-install %{kmod_name}
EOF

# Create modules-load configuration for systemd
install -d %{buildroot}/etc/modules-load.d/
cat > %{buildroot}/etc/modules-load.d/%{kmod_name}.conf << EOF
# Load maccel kernel module at boot
%{kmod_name}
EOF

%files
/lib/modules/%{kmod_kernel_version}/extra/%{kmod_name}/%{kmod_name}.ko
%config(noreplace) /etc/modprobe.d/%{kmod_name}.conf
%config(noreplace) /etc/modules-load.d/%{kmod_name}.conf

%post
# Update module dependencies
/sbin/depmod -a %{kmod_kernel_version} || :

# Load the module if kernel is running the target version
if [ "$(uname -r)" = "%{kmod_kernel_version}" ]; then
    /sbin/modprobe %{kmod_name} || :
fi

%preun
# Unload module before removal if it's loaded
if /sbin/lsmod | grep -q "^%{kmod_name} "; then
    /sbin/modprobe -r %{kmod_name} || :
fi

%postun
# Update module dependencies after removal
/sbin/depmod -a %{kmod_kernel_version} || :

%check
# Basic validation that the module was built correctly
test -f driver/%{kmod_name}.ko
file driver/%{kmod_name}.ko | grep -q "kernel module"

%changelog
# Changelog will be automatically generated during build