# maccel.spec - RPM spec file for maccel userspace tools
# This spec file builds the maccel CLI tools and installs configuration files

%define maccel_driver_version %{?maccel_version}%{!?maccel_version:1.0.0}
%define maccel_rpm_release %{?rpm_release}%{!?rpm_release:1}
%define maccel_kernel_version %{?kernel_version}%{!?kernel_version:6.11.5-300.fc41.x86_64}

Name:           maccel
Version:        %{maccel_driver_version}
Release:        %{maccel_rpm_release}%{?dist}
Summary:        Userspace tools for maccel mouse acceleration driver

License:        GPL-2.0-only
URL:            https://github.com/Gnarus-G/maccel
Source0:        https://github.com/Gnarus-G/maccel/archive/main.tar.gz#/maccel-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root

BuildRequires:  rust >= 1.70
BuildRequires:  cargo
BuildRequires:  gcc

Requires:       kmod-maccel = %{version}-%{release}
Requires(pre):  shadow-utils

%description
The maccel userspace tools provide a command-line interface and text-based UI
for configuring mouse acceleration settings. This package includes the CLI
binary, udev rules for device access, and configuration files.

This package requires the kmod-maccel kernel module to function properly.

%prep
%setup -q -n maccel-%{version}

%build
# Build the CLI using cargo workspace
cargo build --bin maccel --release

%install
# Create installation directories
install -d %{buildroot}%{_bindir}
install -d %{buildroot}/etc/udev/rules.d
install -d %{buildroot}%{_sysconfdir}/maccel

# Install the CLI binary
install -m 755 target/release/maccel %{buildroot}%{_bindir}/maccel

# Install udev rules for device access
install -m 644 udev_rules/99-maccel.rules %{buildroot}/etc/udev/rules.d/99-maccel.rules

# Create default configuration directory (empty for now)
# Users can add their own configuration files here

%files
%{_bindir}/maccel
/etc/udev/rules.d/99-maccel.rules
%dir %{_sysconfdir}/maccel

%pre
# Create maccel group for device access
getent group maccel >/dev/null || groupadd -r maccel

%post
# Reload udev rules to apply device permissions
/sbin/udevadm control --reload-rules || :
/sbin/udevadm trigger || :

%postun
# Clean up group on package removal (only if no other packages use it)
if [ $1 -eq 0 ]; then
    # Check if group is still needed by other packages or users
    if ! getent passwd | cut -d: -f4 | grep -q "$(getent group maccel | cut -d: -f3)" 2>/dev/null; then
        groupdel maccel 2>/dev/null || :
    fi
fi

# Reload udev rules after removal
/sbin/udevadm control --reload-rules || :
/sbin/udevadm trigger || :

%check
# Basic validation that the binary was built correctly
test -f target/release/maccel
test -x target/release/maccel
file target/release/maccel | grep -q "executable"

# Verify udev rules file exists and has correct format
test -f udev_rules/99-maccel.rules
grep -q "maccel" udev_rules/99-maccel.rules

%changelog
# Changelog will be automatically generated during build