#!/usr/bin/env bash
# Uninstall the RPM and confirm the module, flannel fcontext override,
# and vcluster_data_t type are gone from the active policy.
set -ex

rpm -e vcluster-selinux

if semodule -l | grep -q "^vcluster"; then
  echo "FAIL: module still loaded after uninstall"
  exit 1
fi

if semanage fcontext -l -C 2>/dev/null | grep -q "flannel.*container_file_t"; then
  echo "FAIL: flannel fcontext override still present"
  exit 1
fi

if seinfo -t vcluster_data_t 2>/dev/null | grep -qw vcluster_data_t; then
  echo "FAIL: vcluster_data_t still in policy"
  exit 1
fi

echo "PASS: clean uninstall"
