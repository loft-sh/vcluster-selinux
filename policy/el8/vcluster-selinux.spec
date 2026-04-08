%define vcluster_relabel_files() \
        mkdir -p /var/lib/vcluster; \
        restorecon -R -T 0 -i /var/lib/vcluster

%define selinux_policyver 3.14.3-67
%define container_policyver 2.191.0-1
%define container_policy_epoch 3

Name:       vcluster-selinux
Version:    %{vcluster_selinux_version}
Release:    %{vcluster_selinux_release}.el8
Summary:    SELinux policy module for vCluster virtual Kubernetes clusters
Vendor:     Loft Labs
Packager:   Loft Labs <https://www.vcluster.com/>

Group:      System Environment/Base
License:    Apache-2.0
URL:        https://github.com/loft-sh/vcluster-selinux
Source0:    vcluster.pp
Source1:    vcluster.if

BuildArch:      noarch
BuildRequires:  container-selinux >= %{container_policy_epoch}:%{container_policyver}
BuildRequires:  git
BuildRequires:  selinux-policy >= %{selinux_policyver}
BuildRequires:  selinux-policy-devel >= %{selinux_policyver}

Requires:       policycoreutils, libselinux-utils
Requires(post): selinux-policy-base >= %{selinux_policyver}, policycoreutils
Requires(post): container-selinux >= %{container_policy_epoch}:%{container_policyver}
Requires(postun): policycoreutils

Provides:   %{name} = %{version}-%{release}

%description
This package installs and sets up the SELinux policy security module for vCluster.

%install
install -d %{buildroot}%{_datadir}/selinux/packages
install -m 644 %{SOURCE0} %{buildroot}%{_datadir}/selinux/packages
install -d %{buildroot}%{_datadir}/selinux/devel/include/contrib
install -m 644 %{SOURCE1} %{buildroot}%{_datadir}/selinux/devel/include/contrib/
install -d %{buildroot}/etc/selinux/targeted/contexts/users/

%pre
%selinux_relabel_pre

%post
%selinux_modules_install %{_datadir}/selinux/packages/vcluster.pp
if /usr/sbin/selinuxenabled ; then
    /usr/sbin/load_policy
    %vcluster_relabel_files
fi;

%postun
if [ $1 -eq 0 ]; then
    %selinux_modules_uninstall vcluster
fi;

%posttrans
%selinux_relabel_post

%files
%attr(0600,root,root) %{_datadir}/selinux/packages/vcluster.pp
%{_datadir}/selinux/devel/include/contrib/vcluster.if

%changelog
* Tue Apr 08 2026 Loft Labs <support@loft.sh> 0.1-1
- Initial version
