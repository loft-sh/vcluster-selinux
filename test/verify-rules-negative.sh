#!/usr/bin/env bash
# container_t must not reach vcluster_data_t, no container domain may
# relabel it, and vcluster_data_t must not carry the container_file_type
# attribute.
set -ex

for class in file dir; do
  for perm in read write execute; do
    result=$(sesearch --allow -s container_t -t vcluster_data_t -c "$class" -p "$perm" 2>/dev/null | grep "^allow" || true)
    if [ -n "$result" ]; then
      echo "SECURITY FAIL: container_t can $perm vcluster_data_t $class"
      exit 1
    fi
  done
done

for perm in relabelfrom relabelto; do
  result=$(sesearch --allow -t vcluster_data_t -c file -p "$perm" 2>/dev/null | grep "^allow" | grep -E "container_t|container_runtime_t" || true)
  if [ -n "$result" ]; then
    echo "SECURITY FAIL: container domain can $perm vcluster_data_t"
    exit 1
  fi
done

if seinfo -t vcluster_data_t -x 2>/dev/null | grep -q container_file_type; then
  echo "SECURITY FAIL: vcluster_data_t has container_file_type attribute"
  exit 1
fi

echo "PASS: container isolation boundary intact"
