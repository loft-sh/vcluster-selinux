#!/usr/bin/env bats
#
# Runtime enforcement: trigger denials via podman and verify the kernel
# blocks container_t from reaching vcluster_data_t at runtime.
# Complements policy-security.bats which only inspects the rule database.

setup() {
  [ "$(getenforce)" = "Enforcing" ] || skip "SELinux not enforcing"
  semodule -l | grep -q '^vcluster' || skip "vcluster module not loaded"
  command -v podman >/dev/null 2>&1 || skip "podman not installed"
  mkdir -p /var/lib/vcluster/testdata
  echo "sensitive-ca-key-bytes" > /var/lib/vcluster/testdata/secret.txt
  restorecon -R /var/lib/vcluster
  ls -Z /var/lib/vcluster/testdata/secret.txt | grep -q vcluster_data_t
}

teardown() {
  rm -rf /var/lib/vcluster
}

@test "RUNTIME: container_t denied read on vcluster_data_t via volume mount" {
  run podman run --rm -v /var/lib/vcluster/testdata:/mnt:ro \
    docker.io/library/busybox:1.37.0-glibc cat /mnt/secret.txt
  [ "$status" -ne 0 ]
  echo "$output" | grep -qiE "permission denied|eacces"
}

@test "RUNTIME: container_t denied write on vcluster_data_t" {
  run podman run --rm -v /var/lib/vcluster/testdata:/mnt:rw \
    docker.io/library/busybox:1.37.0-glibc sh -c 'echo pwn > /mnt/pwned.txt'
  [ "$status" -ne 0 ]
  [ ! -f /var/lib/vcluster/testdata/pwned.txt ]
}

@test "RUNTIME: container_t denied listing vcluster_data_t dir" {
  run podman run --rm -v /var/lib/vcluster/testdata:/mnt:ro \
    docker.io/library/busybox:1.37.0-glibc ls /mnt
  [ "$status" -ne 0 ]
}
