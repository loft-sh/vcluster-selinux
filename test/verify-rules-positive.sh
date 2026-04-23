#!/usr/bin/env bash
# container_runtime_t must be able to manage vcluster_data_t across every
# object class vcluster creates.
set -ex

for class in file dir sock_file lnk_file fifo_file; do
  sesearch --allow -s container_runtime_t -t vcluster_data_t -c "$class" | grep "^allow" || {
    echo "FAIL: container_runtime_t cannot manage vcluster_data_t $class"
    exit 1
  }
done
echo "PASS: container_runtime_t can manage all vcluster_data_t classes"
