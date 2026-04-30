%define vcluster_relabel_files() \
        umask 0077; \
        mkdir -p /var/lib/vcluster /etc/vcluster; \
        umask 0022; \
        mkdir -p /opt/cni/bin /etc/cni/net.d /opt/local-path-provisioner /run/flannel /run/kubernetes; \
        restorecon -R -T 0 -i /var/lib/vcluster; \
        restorecon -R -T 0 -i /etc/vcluster; \
        restorecon -R -T 0 -i /etc/vcluster-vpn; \
        restorecon -R -T 0 -i /opt/cni; \
        restorecon -R -T 0 -i /etc/cni; \
        restorecon -R -T 0 -i /opt/local-path-provisioner; \
        restorecon -R -T 0 -i /run/flannel; \
        restorecon -R -T 0 -i /run/kubernetes; \
        restorecon -i /etc/crictl.yaml; \
        restorecon -i /usr/local/bin/vcluster-vpn

%define selinux_policyver 40.13.18-1
%define container_policyver 2.240.0-1
%define container_policy_epoch 3

Name:       vcluster-selinux
Version:    %{vcluster_selinux_version}
Release:    %{vcluster_selinux_release}.el10
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
Requires(post): selinux-policy-base >= %{selinux_policyver}, policycoreutils, policycoreutils-python-utils
Requires(post): container-selinux >= %{container_policy_epoch}:%{container_policyver}
Requires(postun): policycoreutils, policycoreutils-python-utils

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
# RHEL 10's policycoreutils rejects fcontext rules on /var/run/* via the
# /var/run -> /run equivalency; register on the canonical path and let
# failures surface (the rule must land or flannel hits a label mismatch).
/usr/sbin/semanage fcontext -a -t container_file_t '/run/flannel(/.*)?' || \
/usr/sbin/semanage fcontext -m -t container_file_t '/run/flannel(/.*)?'
if /usr/sbin/selinuxenabled ; then
    /usr/sbin/load_policy
    %vcluster_relabel_files
fi;

%postun
if [ $1 -eq 0 ]; then
    %selinux_modules_uninstall vcluster
    /usr/sbin/semanage fcontext -d '/run/flannel(/.*)?' 2>/dev/null || true
    if /usr/sbin/selinuxenabled ; then
        restorecon -R -i /var/lib/vcluster 2>/dev/null || true
        restorecon -R -i /etc/vcluster 2>/dev/null || true
        restorecon -R -i /etc/vcluster-vpn 2>/dev/null || true
        restorecon -R -i /opt/cni 2>/dev/null || true
        restorecon -R -i /etc/cni 2>/dev/null || true
        restorecon -R -i /opt/local-path-provisioner 2>/dev/null || true
        restorecon -R -i /run/flannel 2>/dev/null || true
        restorecon -R -i /run/kubernetes 2>/dev/null || true
        restorecon -i /etc/crictl.yaml 2>/dev/null || true
        restorecon -i /usr/local/bin/vcluster-vpn 2>/dev/null || true
    fi
fi;

%posttrans
%selinux_relabel_post

%files
%attr(0600,root,root) %{_datadir}/selinux/packages/vcluster.pp
%{_datadir}/selinux/devel/include/contrib/vcluster.if

%changelog
%include %{changelog_path}
