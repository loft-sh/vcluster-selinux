%global selinuxtype targeted
%global modulename vcluster

Name:           vcluster-selinux
Version:        %{rpm_version}
Release:        %{rpm_release}%{?dist}
Summary:        SELinux policy for vCluster virtual Kubernetes clusters

License:        Apache-2.0
URL:            https://github.com/loft-sh/vcluster-selinux
Source0:        %{name}-%{version}.tar.gz

BuildArch:      noarch
BuildRequires:  selinux-policy-devel
BuildRequires:  git

Requires:       selinux-policy >= %{_selinux_policy_version}
Requires:       container-selinux
Requires(post): selinux-policy-base >= %{_selinux_policy_version}
Requires(post): policycoreutils
Requires(post): policycoreutils-python-utils
Requires(postun): policycoreutils

%description
SELinux policy module for vCluster (virtual Kubernetes clusters).
Provides security contexts for the vcluster syncer and related components.

%prep

%build
make -f /usr/share/selinux/devel/Makefile %{modulename}.pp

%install
install -d %{buildroot}%{_datadir}/selinux/packages
install -m 644 %{modulename}.pp %{buildroot}%{_datadir}/selinux/packages/%{modulename}.pp

%post
semodule -n -i %{_datadir}/selinux/packages/%{modulename}.pp
if /usr/sbin/selinuxenabled; then
    /usr/sbin/load_policy
    /usr/sbin/restorecon -R /var/lib/vcluster 2>/dev/null || :
fi

%postun
if [ $1 -eq 0 ]; then
    semodule -n -r %{modulename} 2>/dev/null || :
    if /usr/sbin/selinuxenabled; then
        /usr/sbin/load_policy
        /usr/sbin/restorecon -R /var/lib/vcluster 2>/dev/null || :
    fi
fi

%files
%license LICENSE
%{_datadir}/selinux/packages/%{modulename}.pp
