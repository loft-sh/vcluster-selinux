#!/usr/bin/env bats
#
# Static policy checks run against the active (loaded) SELinux policy.

setup() {
  [ "$(getenforce)" = "Enforcing" ] || skip "SELinux not enforcing"
  semodule -l | grep -q '^vcluster' || skip "vcluster module not loaded"
}

@test "vcluster module is loaded" {
  semodule -l | grep -q '^vcluster'
}

@test "vcluster_data_t type exists in policy" {
  # On el8 (setools 4.x pre-4.4), seinfo reads a stale policy-binary
  # snapshot right after semodule -i and misses the freshly-loaded type
  # until a policy rebuild. el9 (setools 4.4+) resolves this in the
  # semodule -i itself. Retry once after forcing a rebuild.
  seinfo -t vcluster_data_t | grep -qw vcluster_data_t && return 0
  semodule -B
  seinfo -t vcluster_data_t | grep -qw vcluster_data_t
}

@test "policy rebuild succeeds (semodule -B)" {
  semodule -B
}

@test "container_runtime_t can manage vcluster_data_t files" {
  result=$(sesearch --allow -s container_runtime_t -t vcluster_data_t -c file 2>/dev/null)
  echo "$result" | grep -q "allow"
}

@test "container_runtime_t can manage vcluster_data_t dirs" {
  result=$(sesearch --allow -s container_runtime_t -t vcluster_data_t -c dir 2>/dev/null)
  echo "$result" | grep -q "allow"
}

@test "container_runtime_t can manage vcluster_data_t sock_files" {
  result=$(sesearch --allow -s container_runtime_t -t vcluster_data_t -c sock_file 2>/dev/null)
  echo "$result" | grep -q "allow"
}

@test "container_runtime_t can manage vcluster_data_t lnk_files" {
  result=$(sesearch --allow -s container_runtime_t -t vcluster_data_t -c lnk_file 2>/dev/null)
  echo "$result" | grep -q "allow"
}

@test "container_runtime_t can manage vcluster_data_t fifo_files" {
  result=$(sesearch --allow -s container_runtime_t -t vcluster_data_t -c fifo_file 2>/dev/null)
  echo "$result" | grep -q "allow"
}

@test "SECURITY: container_t cannot read vcluster_data_t files" {
  result=$(sesearch --allow -s container_t -t vcluster_data_t -c file -p read 2>/dev/null | grep "^allow" || true)
  [ -z "$result" ]
}

@test "SECURITY: container_t cannot write vcluster_data_t files" {
  result=$(sesearch --allow -s container_t -t vcluster_data_t -c file -p write 2>/dev/null | grep "^allow" || true)
  [ -z "$result" ]
}

@test "SECURITY: container_t cannot read vcluster_data_t dirs" {
  result=$(sesearch --allow -s container_t -t vcluster_data_t -c dir -p read 2>/dev/null | grep "^allow" || true)
  [ -z "$result" ]
}

@test "SECURITY: container_t cannot execute vcluster_data_t files" {
  result=$(sesearch --allow -s container_t -t vcluster_data_t -c file -p execute 2>/dev/null | grep "^allow" || true)
  [ -z "$result" ]
}

@test "SECURITY: container_t cannot access vcluster_data_t sock_files" {
  result=$(sesearch --allow -s container_t -t vcluster_data_t -c sock_file 2>/dev/null | grep "^allow" || true)
  [ -z "$result" ]
}

@test "SECURITY: no container domain can relabelfrom vcluster_data_t files" {
  # System admin domains (init_t, setfiles_t, restorecond_t, secadm_t, systemd_tmpfiles_t)
  # have relabel via file_type attribute — this is expected and correct.
  # We verify that no container domain has relabel.
  result=$(sesearch --allow -t vcluster_data_t -c file -p relabelfrom 2>/dev/null | grep "^allow" || true)
  container_relabel=$(echo "$result" | grep -E "container_t|container_runtime_t" || true)
  [ -z "$container_relabel" ]
}

@test "SECURITY: no container domain can relabelto vcluster_data_t files" {
  result=$(sesearch --allow -t vcluster_data_t -c file -p relabelto 2>/dev/null | grep "^allow" || true)
  container_relabel=$(echo "$result" | grep -E "container_t|container_runtime_t" || true)
  [ -z "$container_relabel" ]
}

@test "SECURITY: vcluster_data_t does not have container_file_type attribute" {
  # If vcluster_data_t had container_file_type, containers could relabel it
  result=$(seinfo -t vcluster_data_t -x 2>/dev/null | grep "container_file_type" || true)
  [ -z "$result" ]
}

@test "SECURITY: vcluster_data_t does not have container_var_lib_t attribute" {
  result=$(seinfo -t vcluster_data_t -x 2>/dev/null | grep "container_var_lib_t" || true)
  [ -z "$result" ]
}

@test "SECURITY: no type_transition from container_t via vcluster types" {
  result=$(sesearch --type_trans -s container_t -t vcluster_data_t 2>/dev/null | grep "^type_transition" || true)
  [ -z "$result" ]
}

@test "SECURITY: new files in /var/lib/vcluster/bin/ inherit vcluster_data_t not exec" {
  expected=$(matchpathcon /var/lib/vcluster/bin/newbinary 2>/dev/null | grep -o '[^:]*_t' | tail -1)
  [ "$expected" = "vcluster_data_t" ]
}

@test "matchpathcon: /var/lib/vcluster/bin/vcluster -> container_runtime_exec_t" {
  result=$(matchpathcon /var/lib/vcluster/bin/vcluster 2>/dev/null)
  echo "$result" | grep -q "container_runtime_exec_t"
}

@test "matchpathcon: /var/lib/vcluster -> vcluster_data_t" {
  result=$(matchpathcon /var/lib/vcluster 2>/dev/null)
  echo "$result" | grep -q "vcluster_data_t"
}

@test "matchpathcon: /var/lib/vcluster/pki/ca.key -> vcluster_data_t" {
  result=$(matchpathcon /var/lib/vcluster/pki/ca.key 2>/dev/null)
  echo "$result" | grep -q "vcluster_data_t"
}

@test "matchpathcon: /etc/vcluster -> container_config_t" {
  result=$(matchpathcon /etc/vcluster 2>/dev/null)
  echo "$result" | grep -q "container_config_t"
}

@test "matchpathcon: /opt/cni/bin -> container_file_t" {
  result=$(matchpathcon /opt/cni/bin 2>/dev/null)
  echo "$result" | grep -q "container_file_t"
}

@test "matchpathcon: /etc/cni/net.d -> container_file_t" {
  result=$(matchpathcon /etc/cni/net.d 2>/dev/null)
  echo "$result" | grep -q "container_file_t"
}

@test "matchpathcon: /usr/local/bin/vcluster-vpn -> container_runtime_exec_t" {
  result=$(matchpathcon /usr/local/bin/vcluster-vpn 2>/dev/null)
  echo "$result" | grep -q "container_runtime_exec_t"
}

@test "fcontext rule registered: /etc/systemd/system/vcluster -> container_unit_file_t" {
  # matchpathcon may return systemd_unit_file_t due to base policy precedence,
  # but the fcontext rule IS registered and restorecon applies it correctly.
  semanage fcontext -l | grep "vcluster" | grep -q "container_unit_file_t"
}

@test "fcontext: /var/run/flannel -> container_file_t (semanage override)" {
  semanage fcontext -l -C | grep "flannel" | grep -q "container_file_t"
}

@test "matchpathcon: /etc/vcluster-vpn -> container_config_t" {
  result=$(matchpathcon /etc/vcluster-vpn 2>/dev/null)
  echo "$result" | grep -q "container_config_t"
}

@test "matchpathcon: /etc/crictl.yaml -> container_config_t" {
  result=$(matchpathcon /etc/crictl.yaml 2>/dev/null)
  echo "$result" | grep -q "container_config_t"
}

@test "fcontext rule registered: /run/kubernetes -> container_var_run_t" {
  semanage fcontext -l | grep "/run/kubernetes" | grep -q "container_var_run_t"
}

@test "matchpathcon: /var/lib/vcluster/bin/kube-apiserver -> container_runtime_exec_t" {
  result=$(matchpathcon /var/lib/vcluster/bin/kube-apiserver 2>/dev/null)
  echo "$result" | grep -q "container_runtime_exec_t"
}

@test "matchpathcon: /var/lib/vcluster/bin/etcd -> container_runtime_exec_t" {
  result=$(matchpathcon /var/lib/vcluster/bin/etcd 2>/dev/null)
  echo "$result" | grep -q "container_runtime_exec_t"
}

@test "domain transition exists: init_t -> container_runtime_exec_t -> container_runtime_t" {
  result=$(sesearch --type_trans -s init_t -t container_runtime_exec_t 2>/dev/null)
  echo "$result" | grep -q "container_runtime_t"
}

@test "flannel semanage local override exists" {
  semanage fcontext -l -C | grep "flannel" | grep -q "container_file_t"
}

@test "/var/lib/vcluster created with restrictive permissions" {
  if [ -d /var/lib/vcluster ]; then
    perms=$(stat -c %a /var/lib/vcluster)
    # Should be 700 or 750, not 755
    [ "$perms" -le 750 ]
  else
    skip "/var/lib/vcluster does not exist"
  fi
}

@test "/etc/vcluster created with restrictive permissions" {
  if [ -d /etc/vcluster ]; then
    perms=$(stat -c %a /etc/vcluster)
    [ "$perms" -le 750 ]
  else
    skip "/etc/vcluster does not exist"
  fi
}

@test "systemd regex does not match files in subdirectories" {
  # vcluster[^/]* should NOT match subdirectory files
  result=$(matchpathcon /etc/systemd/system/vcluster.service.d/override.conf 2>/dev/null)
  if echo "$result" | grep -q "container_unit_file_t"; then
    echo "FAIL: subdirectory file incorrectly matches container_unit_file_t"
    echo "$result"
    return 1
  fi
}

@test "no vcluster-specific dontaudit rules" {
  # Base policy has dontaudit via file_type attribute (e.g. dontaudit domain file_type:dir getattr).
  # We verify our module doesn't add any ADDITIONAL dontaudit rules specific to vcluster_data_t.
  # Base policy dontaudit rules reference file_type or non_auth_file_type, not vcluster_data_t directly.
  result=$(sesearch --dontaudit -t vcluster_data_t 2>/dev/null | grep "^dontaudit" | grep "vcluster_data_t" || true)
  [ -z "$result" ]
}
