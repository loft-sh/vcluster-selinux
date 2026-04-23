#!/usr/bin/env bats
#
# Uninstall + reinstall cycle. Must run last: bats sorts by filename.
# Expects the RPM at /tmp/vcluster-selinux.rpm.

setup() {
  [ "$(getenforce)" = "Enforcing" ] || skip "SELinux not enforcing"
  command -v semanage >/dev/null 2>&1 || skip "semanage required"
}

@test "UNINSTALL: RPM removes cleanly" {
  rpm -q vcluster-selinux
  dnf remove -y vcluster-selinux 2>&1 | tail -5
  ! rpm -q vcluster-selinux
}

@test "UNINSTALL: vcluster module is unloaded" {
  ! semodule -l | grep -q '^vcluster'
}

@test "UNINSTALL: vcluster_data_t type no longer in active policy" {
  ! seinfo -t vcluster_data_t 2>/dev/null | grep -q vcluster_data_t
}

@test "UNINSTALL: no vcluster file-context entries in semanage DB" {
  ! semanage fcontext -l | grep -qE '(^|/)vcluster'
}

@test "UNINSTALL: flannel semanage override is removed" {
  ! semanage fcontext -l -C 2>/dev/null | grep -q 'flannel.*container_file_t'
}

@test "UNINSTALL: restorecon on vcluster paths does not relabel to vcluster_data_t" {
  mkdir -p /var/lib/vcluster
  touch /var/lib/vcluster/post-uninstall
  restorecon -R /var/lib/vcluster
  ctx=$(ls -Z /var/lib/vcluster/post-uninstall | awk '{print $1}')
  ! echo "$ctx" | grep -q vcluster_data_t
  rm -rf /var/lib/vcluster/post-uninstall
}

@test "REINSTALL: RPM installs cleanly after prior uninstall" {
  dnf install -y /tmp/vcluster-selinux.rpm 2>&1 | tail -3
  rpm -q vcluster-selinux
}

@test "REINSTALL: vcluster module is loaded again" {
  semodule -l | grep -q '^vcluster'
}

@test "REINSTALL: vcluster_data_t type is back in active policy" {
  seinfo -t vcluster_data_t | grep -qw vcluster_data_t
}

@test "REINSTALL: file contexts resolve to expected types again" {
  matchpathcon /var/lib/vcluster/bin/vcluster | grep -q container_runtime_exec_t
  matchpathcon /var/lib/vcluster | grep -q vcluster_data_t
}

@test "REINSTALL: flannel semanage override is restored" {
  semanage fcontext -l -C | grep 'flannel' | grep -q container_file_t
}
