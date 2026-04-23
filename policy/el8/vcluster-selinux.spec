%define vcluster_relabel_files() \
        umask 0077; \
        mkdir -p /var/lib/vcluster /etc/vcluster; \
        umask 0022; \
        mkdir -p /opt/cni/bin /etc/cni/net.d /run/flannel /run/kubernetes; \
        restorecon -R -i /var/lib/vcluster; \
        restorecon -R -i /etc/vcluster; \
        restorecon -R -i /etc/vcluster-vpn; \
        restorecon -R -i /opt/cni; \
        restorecon -R -i /etc/cni; \
        restorecon -R -i /run/flannel; \
        restorecon -R -i /run/kubernetes; \
        restorecon -i /etc/crictl.yaml; \
        restorecon -i /usr/local/bin/vcluster-vpn

%define selinux_policyver 3.14.3-67
%define container_policyver 2.167.0-1
%define container_policy_epoch 2

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
/usr/sbin/semanage fcontext -a -t container_file_t '/var/run/flannel(/.*)?' 2>/dev/null || \
/usr/sbin/semanage fcontext -m -t container_file_t '/var/run/flannel(/.*)?' || true
if /usr/sbin/selinuxenabled ; then
    /usr/sbin/load_policy
    %vcluster_relabel_files
fi;

%postun
if [ $1 -eq 0 ]; then
    %selinux_modules_uninstall vcluster
    /usr/sbin/semanage fcontext -d '/var/run/flannel(/.*)?' 2>/dev/null || true
    if /usr/sbin/selinuxenabled ; then
        restorecon -R -i /var/lib/vcluster 2>/dev/null || true
        restorecon -R -i /etc/vcluster 2>/dev/null || true
        restorecon -R -i /etc/vcluster-vpn 2>/dev/null || true
        restorecon -R -i /opt/cni 2>/dev/null || true
        restorecon -R -i /etc/cni 2>/dev/null || true
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
* Wed Apr 16 2026 Loft Labs <support@loft.sh> 0.2-1
- Replace stub policy with AVC-profiled policy for standalone and private nodes
- Add file contexts for vcluster binaries, configs, CNI, VPN, and runtime dirs
- Add semanage override for /run/flannel (container_file_t)
- Add policycoreutils-python-utils dependency for semanage
- Remove vcluster_syncer_t domain; processes run as container_runtime_t

* Tue Apr 08 2026 Loft Labs <support@loft.sh> 0.1-1
- Initial version
