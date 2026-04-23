#!/usr/bin/env bash
# Every path declared in the .fc file must resolve to its expected type.
set -ex

matchpathcon /var/lib/vcluster/bin/vcluster       | grep container_runtime_exec_t
matchpathcon /var/lib/vcluster/bin/kube-apiserver | grep container_runtime_exec_t
matchpathcon /var/lib/vcluster/bin/etcd           | grep container_runtime_exec_t
matchpathcon /var/lib/vcluster                    | grep vcluster_data_t
matchpathcon /var/lib/vcluster/pki/ca.key         | grep vcluster_data_t
matchpathcon /etc/vcluster                        | grep container_config_t
matchpathcon /etc/vcluster-vpn                    | grep container_config_t
matchpathcon /opt/cni/bin                         | grep container_file_t
matchpathcon /etc/cni/net.d                       | grep container_file_t
matchpathcon /usr/local/bin/vcluster-vpn          | grep container_runtime_exec_t
matchpathcon /etc/crictl.yaml                     | grep container_config_t

# New binaries under /var/lib/vcluster/bin/ must NOT auto-inherit runtime exec.
matchpathcon /var/lib/vcluster/bin/unknown-new-binary | grep vcluster_data_t

semanage fcontext -l -C | grep flannel | grep container_file_t

echo "PASS: all file contexts correct"
