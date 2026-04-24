#!/usr/bin/env bash
# Boot a cloud-init VM with SELinux enforcing, copy in an RPM and a bats
# directory, run the tests. Requires /dev/kvm on the host.
set -euo pipefail

RPM_PATH="$(readlink -f "${1:?rpm path required}")"
BATS_PATH="$(readlink -f "${2:?bats path required}")"
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vm-test"

VM_MEMORY_MB="${VM_MEMORY_MB:-6144}"
VM_CPUS="${VM_CPUS:-4}"
VM_BOOT_TIMEOUT="${VM_BOOT_TIMEOUT:-480}"
# Default is for local runs; CI overrides this per matrix entry (AlmaLinux 9,
# Rocky 8, etc.) via the VM_IMAGE_URL env var from e2e-selinux.yml.
VM_IMAGE_URL="${VM_IMAGE_URL:-https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2}"

WORKDIR="$(mktemp -d)"
trap 'cleanup' EXIT

cleanup() {
  if [[ -n "${QEMU_PID:-}" ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
    echo "--- shutting down VM (pid $QEMU_PID) ---"
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  if [[ -f "$WORKDIR/qemu.log" ]]; then
    cp "$WORKDIR/qemu.log" "${QEMU_LOG_DEST:-/tmp/qemu.log}" || true
  fi
  rm -rf "$WORKDIR"
}

echo "=== Setup workspace: $WORKDIR ==="
cd "$WORKDIR"

echo "=== Check KVM availability ==="
if [[ ! -e /dev/kvm ]]; then
  echo "ERROR: /dev/kvm not present on this runner"
  exit 1
fi
ls -l /dev/kvm

echo "=== Download CentOS Stream 9 cloud image ==="
curl --fail --silent --show-error --location "$VM_IMAGE_URL" -o base.qcow2
if [[ -n "${VM_IMAGE_SHA256:-}" ]]; then
  echo "$VM_IMAGE_SHA256  base.qcow2" | sha256sum -c -
fi

echo "=== Create overlay disk (20G, backed by base) ==="
qemu-img create -f qcow2 -F qcow2 -b "$WORKDIR/base.qcow2" disk.qcow2 20G

echo "=== Generate ephemeral SSH keypair ==="
ssh-keygen -t ed25519 -N '' -f id_rsa -C 'selinux-e2e' >/dev/null

echo "=== Render cloud-init seed ==="
SSH_PUBKEY="$(cat id_rsa.pub)"
sed "s|__SSH_AUTHORIZED_KEY__|${SSH_PUBKEY}|" "$FIXTURES/user-data.yaml.tmpl" > user-data
cp "$FIXTURES/meta-data.yaml" meta-data
cloud-localds seed.iso user-data meta-data

echo "=== Boot VM ==="
QEMU_LOG="$WORKDIR/qemu.log"
qemu-system-x86_64 \
  -name selinux-e2e \
  -machine accel=kvm,type=q35 \
  -cpu host \
  -m "$VM_MEMORY_MB" \
  -smp "$VM_CPUS" \
  -drive "if=virtio,format=qcow2,file=$WORKDIR/disk.qcow2" \
  -drive "if=virtio,format=raw,file=$WORKDIR/seed.iso,readonly=on" \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 \
  -device virtio-net-pci,netdev=n0 \
  -display none \
  -serial "file:$QEMU_LOG" \
  -daemonize \
  -pidfile "$WORKDIR/qemu.pid"

QEMU_PID="$(cat "$WORKDIR/qemu.pid")"
echo "QEMU pid: $QEMU_PID"

SSH_COMMON=(
  -i "$WORKDIR/id_rsa"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout=5
)
SSH_OPTS=("${SSH_COMMON[@]}" -p 2222)
SCP_OPTS=("${SSH_COMMON[@]}" -P 2222)

echo "=== Wait for SSH (timeout ${VM_BOOT_TIMEOUT}s) ==="
deadline=$(( $(date +%s) + VM_BOOT_TIMEOUT ))
while true; do
  if ssh "${SSH_OPTS[@]}" tester@127.0.0.1 'echo ok' >/dev/null 2>&1; then
    echo "SSH is up"
    break
  fi
  if (( $(date +%s) >= deadline )); then
    echo "ERROR: VM did not become reachable within ${VM_BOOT_TIMEOUT}s"
    echo "--- serial console tail ---"
    tail -n 200 "$QEMU_LOG" || true
    exit 1
  fi
  sleep 3
done

echo "=== Wait for cloud-init to finish ==="
ssh "${SSH_OPTS[@]}" tester@127.0.0.1 'sudo cloud-init status --wait' || {
  echo "ERROR: cloud-init did not complete cleanly"
  exit 1
}

# bootcmd edited grub but deliberately didn't reboot (see the note there).
# If the host is still on cgroup v1 at this point, trigger the reboot
# from here and wait for SSH to come back.
CGROUP_FS=$(ssh "${SSH_OPTS[@]}" tester@127.0.0.1 'stat -fc %T /sys/fs/cgroup')
if [[ "$CGROUP_FS" != "cgroup2fs" ]]; then
  echo "=== Rebooting VM to activate cgroup v2 (was $CGROUP_FS) ==="
  ssh "${SSH_OPTS[@]}" tester@127.0.0.1 'sudo systemctl reboot' 2>/dev/null || true
  # wait for the SSH port to drop, then come back on cgroup v2
  sleep 15
  deadline=$(( $(date +%s) + 180 ))
  while true; do
    POST=$(ssh "${SSH_OPTS[@]}" tester@127.0.0.1 'stat -fc %T /sys/fs/cgroup' 2>/dev/null || true)
    if [[ "$POST" == "cgroup2fs" ]]; then
      echo "cgroup v2 active after reboot"
      break
    fi
    if (( $(date +%s) >= deadline )); then
      echo "ERROR: VM did not return on cgroup v2 after reboot"
      tail -n 200 "$QEMU_LOG" || true
      exit 1
    fi
    sleep 5
  done
fi

echo "=== Verify SELinux is enforcing ==="
ssh "${SSH_OPTS[@]}" tester@127.0.0.1 'getenforce' | tee enforce.out
grep -q '^Enforcing$' enforce.out

echo "=== Install test dependencies ==="
# bats lives in EPEL, not default repos.
ssh "${SSH_OPTS[@]}" tester@127.0.0.1 '
  sudo dnf install -y epel-release
  sudo dnf install -y bats setools-console policycoreutils-python-utils container-selinux podman
'

echo "=== Copy RPM and BATS suite(s) ==="
scp "${SCP_OPTS[@]}" "$RPM_PATH" tester@127.0.0.1:/tmp/vcluster-selinux.rpm
ssh "${SSH_OPTS[@]}" tester@127.0.0.1 'rm -rf /tmp/bats && mkdir -p /tmp/bats'
if [[ -d "$BATS_PATH" ]]; then
  scp -r "${SCP_OPTS[@]}" "$BATS_PATH"/*.bats tester@127.0.0.1:/tmp/bats/
else
  scp "${SCP_OPTS[@]}" "$BATS_PATH" tester@127.0.0.1:/tmp/bats/
fi

echo "=== Install RPM ==="
ssh "${SSH_OPTS[@]}" tester@127.0.0.1 'sudo dnf install -y /tmp/vcluster-selinux.rpm'

echo "=== Run BATS suite ==="
set +e
ssh "${SSH_OPTS[@]}" tester@127.0.0.1 'sudo bats /tmp/bats/'
BATS_RESULT=$?
set -e

if [[ $BATS_RESULT -ne 0 ]]; then
  echo "=== BATS TESTS FAILED (exit $BATS_RESULT) ==="
  echo "--- recent AVCs (auditd + kernel log) ---"
  ssh "${SSH_OPTS[@]}" tester@127.0.0.1 '
    sudo ausearch -m avc -ts recent 2>/dev/null || true
    sudo journalctl -k --since "5 min ago" 2>/dev/null | grep -i avc || true
    sudo dmesg 2>/dev/null | grep -i avc | tail -30 || true
  ' || true
  exit "$BATS_RESULT"
fi
echo "=== BATS PASSED ==="

VCLUSTER_VERSION="${VCLUSTER_VERSION:-v0.34.0-alpha.5}"
POD_READY_TIMEOUT="${POD_READY_TIMEOUT:-240}"
INSTALLER_URL="${INSTALLER_URL:-https://github.com/loft-sh/vcluster/releases/download/${VCLUSTER_VERSION}/install-standalone.sh}"

echo "=== Fetch install-standalone.sh (${VCLUSTER_VERSION}) ==="
curl --fail --silent --show-error --location "$INSTALLER_URL" -o "$WORKDIR/install-standalone.sh"
chmod +x "$WORKDIR/install-standalone.sh"
scp "${SCP_OPTS[@]}" "$WORKDIR/install-standalone.sh" tester@127.0.0.1:/tmp/install-standalone.sh

CONFIG_FLAG=""
if [[ -n "${K8S_VERSION_OVERRIDE:-}" ]]; then
  echo "=== Pin kubernetes to ${K8S_VERSION_OVERRIDE} (host glibc compatibility) ==="
  sed "s|__K8S_VERSION__|${K8S_VERSION_OVERRIDE}|" "$FIXTURES/vcluster-k8s-pin.yaml.tmpl" > "$WORKDIR/vcluster.yaml"
  scp "${SCP_OPTS[@]}" "$WORKDIR/vcluster.yaml" tester@127.0.0.1:/tmp/vcluster.yaml
  CONFIG_FLAG="--config /tmp/vcluster.yaml"
fi

INSTALL_START=$(ssh "${SSH_OPTS[@]}" tester@127.0.0.1 "date '+%H:%M:%S'")

echo "=== Run install-standalone.sh (${VCLUSTER_VERSION}${K8S_VERSION_OVERRIDE:+ / k8s ${K8S_VERSION_OVERRIDE}}) ==="
set +e
ssh "${SSH_OPTS[@]}" tester@127.0.0.1 "
  sudo /tmp/install-standalone.sh --vcluster-version ${VCLUSTER_VERSION} --skip-selinux-rpm --skip-wait --containerd-selinux ${CONFIG_FLAG}
"
INSTALL_RC=$?
set -e
if [[ $INSTALL_RC -ne 0 ]]; then
  echo "=== install-standalone.sh exited $INSTALL_RC — capturing diagnostics ==="
  ssh "${SSH_OPTS[@]}" tester@127.0.0.1 '
    echo "--- ls -lZ /var/lib/vcluster/bin ---"
    sudo ls -lZ /var/lib/vcluster/bin 2>/dev/null || true
    echo "--- systemctl status vcluster.service ---"
    sudo systemctl status vcluster.service --no-pager -l || true
    echo "--- journalctl -u vcluster.service (last 100) ---"
    sudo journalctl -u vcluster.service --no-pager -n 100 || true
    echo "--- recent AVCs ---"
    sudo ausearch -m avc -ts recent 2>/dev/null | head -60 || true
  ' || true
  exit 1
fi

echo "=== Wait for kubelet (max 5 min) ==="
ssh "${SSH_OPTS[@]}" tester@127.0.0.1 '
  for i in $(seq 1 60); do
    if sudo systemctl is-active --quiet kubelet.service; then
      echo "kubelet active after $((i*5))s"; exit 0
    fi
    sleep 5
  done
  echo "ERROR: kubelet did not come up"
  echo "--- cgroup version ---"
  stat -fc %T /sys/fs/cgroup
  echo "--- systemctl status kubelet.service ---"
  sudo systemctl status kubelet.service --no-pager -l || true
  echo "--- journalctl -u kubelet.service (last 100) ---"
  sudo journalctl -u kubelet.service --no-pager -n 100 || true
  echo "--- systemctl status containerd.service ---"
  sudo systemctl status containerd.service --no-pager -l || true
  echo "--- journalctl -u containerd.service (last 100) ---"
  sudo journalctl -u containerd.service --no-pager -n 100 || true
  echo "--- kubeadm init output (last 60) ---"
  sudo journalctl -u vcluster.service --no-pager -n 60 || true
  echo "--- /var/lib/vcluster/bin (top level, labels) ---"
  sudo ls -lZ /var/lib/vcluster/bin 2>/dev/null || true
  echo "--- /var/lib/vcluster/bin/kubernetes-*/bin labels (where containerd/kubelet actually live) ---"
  sudo find /var/lib/vcluster/bin -maxdepth 4 -type f \( -name containerd -o -name containerd-shim-runc-v2 -o -name runc -o -name kubelet -o -name kubeadm \) -exec ls -lZ {} \; 2>/dev/null | head -20
  echo "--- /etc/systemd/system/containerd.service (ExecStart) ---"
  sudo grep -E "^(ExecStart|Environment)" /etc/systemd/system/containerd.service 2>/dev/null || true
  echo "--- /etc/containerd/config.toml (first 80) ---"
  sudo head -80 /etc/containerd/config.toml 2>/dev/null || true
  echo "--- AVCs since install start ---"
  sudo ausearch -m avc -ts recent 2>/dev/null | head -60 || true
  exit 1
'

echo "=== Wait for ≥5 control-plane pods Running (max ${POD_READY_TIMEOUT}s) ==="
ssh "${SSH_OPTS[@]}" tester@127.0.0.1 "
  set -e
  export KUBECONFIG=/var/lib/vcluster/kubeconfig.yaml
  deadline=\$((\$(date +%s) + ${POD_READY_TIMEOUT}))
  while true; do
    ready=\$(sudo -E /usr/local/bin/kubectl get pods -A --no-headers 2>/dev/null | awk '\$4==\"Running\" && \$3~/^[1-9]\\/[1-9]\$/ {c++} END{print c+0}')
    echo \"  ready=\$ready\"
    if [ \"\$ready\" -ge 5 ]; then break; fi
    if [ \"\$(date +%s)\" -ge \"\$deadline\" ]; then
      echo 'ERROR: pods never reached 5 Running'
      K=/usr/local/bin/kubectl
      sudo -E \$K get pods -A -o wide || true
      echo '--- events (last 40) ---'
      sudo -E \$K get events -A --sort-by=.lastTimestamp | tail -40 || true
      echo '--- flannel kubelet-side logs (per container, prev + current, NO stderr suppression) ---'
      FPOD=\$(sudo -E \$K get pods -n kube-flannel -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
      echo \"pod=\$FPOD\"
      for c in install-cni-plugin install-cni kube-flannel; do
        echo \"--- logs prev -c \$c ---\"
        sudo -E \$K logs -n kube-flannel \$FPOD -c \$c --previous || true
        echo \"--- logs cur -c \$c ---\"
        sudo -E \$K logs -n kube-flannel \$FPOD -c \$c || true
      done
      echo '--- ctr (containerd native) ---'
      sudo ctr -n k8s.io containers ls 2>&1 | grep -E 'flannel|coredns|local-path' | head -10 || true
      echo '--- /var/log/pods tree ---'
      sudo find /var/log/pods -maxdepth 3 2>&1 | head -30
      echo '--- flannel + coredns container logs (all attempts) ---'
      sudo find /var/log/pods -path '*kube-flannel*' -name '*.log' 2>/dev/null | while read f; do
        echo \":::: \$f ::::\"
        sudo tail -80 \"\$f\" 2>&1 || true
      done
      sudo find /var/log/pods -path '*coredns*' -name '*.log' 2>/dev/null | while read f; do
        echo \":::: \$f ::::\"
        sudo tail -40 \"\$f\" 2>&1 || true
      done
      echo '--- container-selinux + kernel version ---'
      sudo rpm -q container-selinux selinux-policy kernel 2>&1 | tail -5
      sudo uname -a
      echo '--- kubelet journal (last 100) ---'
      sudo journalctl -u kubelet.service --no-pager -n 100 || true
      echo '--- containerd journal (last 60) ---'
      sudo journalctl -u containerd.service --no-pager -n 60 || true
      echo '--- dmesg tail ---'
      sudo dmesg | tail -60 || true
      echo '--- kernel modules (vxlan / bridge / iptable) ---'
      sudo lsmod | grep -E 'vxlan|bridge|nf_|iptable|xt_' || echo '(none)'
      echo '--- sysctl net ---'
      sudo sysctl net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward 2>&1 || true
      echo '--- AVCs since install start ---'
      sudo ausearch -m avc -ts recent 2>&1 | tail -80 || true
      echo '--- /run/flannel state ---'
      sudo ls -lZ /run/flannel 2>&1 || true
      exit 1
    fi
    sleep 10
  done
  sudo -E /usr/local/bin/kubectl get pods -A
"

echo "=== Smoke: default-StorageClass PVC must Bind and a pod must mount it (regression guard for ENGNODE-344) ==="
scp "${SCP_OPTS[@]}" "$FIXTURES/pvc-smoke.yaml" tester@127.0.0.1:/tmp/pvc-smoke.yaml
ssh "${SSH_OPTS[@]}" tester@127.0.0.1 'bash -s' <<'REMOTE'
set -e
export KUBECONFIG=/var/lib/vcluster/kubeconfig.yaml
K=/usr/local/bin/kubectl
sudo -E $K apply -f /tmp/pvc-smoke.yaml
for i in $(seq 1 36); do
  phase=$(sudo -E $K get pvc ci-pvc -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$phase" = "Bound" ] && break
  sleep 5
done
for i in $(seq 1 24); do
  pod_phase=$(sudo -E $K get pod ci-pvc-consumer -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$pod_phase" = "Running" ] || [ "$pod_phase" = "Succeeded" ] && break
  sleep 5
done
echo "PVC phase=$phase pod phase=$pod_phase"
if [ "$phase" != "Bound" ] || { [ "$pod_phase" != "Running" ] && [ "$pod_phase" != "Succeeded" ]; }; then
  echo "FAIL: PVC or pod did not reach expected state"
  sudo -E $K describe pvc ci-pvc
  sudo -E $K describe pod ci-pvc-consumer
  sudo -E $K get pods -n local-path-storage -o wide
  sudo -E $K -n local-path-storage logs deploy/local-path-provisioner --tail=80 || true
  exit 1
fi
REMOTE

PLATFORM_TIMEOUT="${PLATFORM_TIMEOUT:-600}"
VCLUSTER_CREATE_TIMEOUT="${VCLUSTER_CREATE_TIMEOUT:-600}"

echo "=== Install helm ==="
ssh "${SSH_OPTS[@]}" tester@127.0.0.1 '
  set -e
  HELM_V="v3.20.2"
  A=$(uname -m | sed "s/aarch64/arm64/;s/x86_64/amd64/")
  curl -sfL "https://get.helm.sh/helm-${HELM_V}-linux-${A}.tar.gz" -o /tmp/helm.tgz
  sudo tar -xzf /tmp/helm.tgz -C /usr/local/bin --strip-components=1 "linux-${A}/helm"
  sudo chmod +x /usr/local/bin/helm
  /usr/local/bin/helm version --short
'

echo "=== helm install vcluster-platform (no license) ==="
ADMIN_PASSWORD="$(openssl rand -hex 16)"
set +e
ssh "${SSH_OPTS[@]}" tester@127.0.0.1 "
  set -e
  export KUBECONFIG=/var/lib/vcluster/kubeconfig.yaml
  sudo -E /usr/local/bin/helm upgrade vcluster-platform vcluster-platform \
    --install --repo https://charts.loft.sh/ \
    --namespace vcluster-platform --create-namespace \
    --set admin.password=${ADMIN_PASSWORD} \
    --wait --timeout ${PLATFORM_TIMEOUT}s
"
PLATFORM_RC=$?
set -e
if [[ $PLATFORM_RC -ne 0 ]]; then
  echo "=== vcluster-platform helm install exit $PLATFORM_RC — diagnostics ==="
  ssh "${SSH_OPTS[@]}" tester@127.0.0.1 '
    export KUBECONFIG=/var/lib/vcluster/kubeconfig.yaml
    echo "--- pods in vcluster-platform ---"
    sudo -E /usr/local/bin/kubectl -n vcluster-platform get pods -o wide || true
    echo "--- events ---"
    sudo -E /usr/local/bin/kubectl -n vcluster-platform get events --sort-by=.lastTimestamp | tail -40 || true
    echo "--- loft deployment logs ---"
    sudo -E /usr/local/bin/kubectl -n vcluster-platform logs deploy/loft --tail=100 || true
  ' || true
  exit 1
fi

echo "=== Wait for loft-router domain + loft pod Ready ==="
ssh "${SSH_OPTS[@]}" tester@127.0.0.1 '
  export KUBECONFIG=/var/lib/vcluster/kubeconfig.yaml
  for i in $(seq 1 60); do
    d=$(sudo -E /usr/local/bin/kubectl get secret loft-router-domain -n vcluster-platform -o jsonpath="{.data.domain}" 2>/dev/null | base64 -d 2>/dev/null)
    if [ -n "$d" ]; then echo "platform domain: $d"; break; fi
    sleep 5
  done
  sudo -E /usr/local/bin/kubectl -n vcluster-platform wait --for=condition=Ready pod -l app=loft --timeout=300s
  sudo -E /usr/local/bin/kubectl -n vcluster-platform get pods
'

echo "=== Assert zero vcluster/container AVCs since ${INSTALL_START} ==="
# Match AVCs attributable to our policy: either the target type is one of ours
# (tcontext ...:vcluster_*) or the source domain is container-selinux's runtime
# domain (scontext ...:container_runtime_t / container_t). Broader patterns catch
# unrelated messages like 'container_file_t' denials from other packages.
AVC_COUNT=$(ssh "${SSH_OPTS[@]}" tester@127.0.0.1 "sudo ausearch -m avc --start ${INSTALL_START} 2>/dev/null | grep -cE 'tcontext=[^ ]*:vcluster_|scontext=[^ ]*:(container_runtime_t|container_t)' || true" | tr -d '[:space:]')
echo "vcluster/container AVCs since install-standalone: $AVC_COUNT"
if [[ "$AVC_COUNT" != "0" ]]; then
  echo "FAIL: unexpected AVCs from our policy types during install flow"
  ssh "${SSH_OPTS[@]}" tester@127.0.0.1 "sudo ausearch -m avc --start ${INSTALL_START} 2>/dev/null | grep -E 'tcontext=[^ ]*:vcluster_|scontext=[^ ]*:(container_runtime_t|container_t)' | sort -u"
  exit 1
fi

echo "=== Verify install-standalone.sh --reset-only cleans up ==="
ssh "${SSH_OPTS[@]}" tester@127.0.0.1 '
  sudo /tmp/install-standalone.sh --reset-only
  ! sudo systemctl is-active --quiet vcluster.service
  [ ! -d /var/lib/vcluster ] || { echo "FAIL: /var/lib/vcluster still present"; exit 1; }
  echo "PASS: clean reset"
'

echo "=== ALL CHECKS PASSED ==="
exit 0
