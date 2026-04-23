#!/usr/bin/env bash
# Install the RPM plus tooling required by the other verify-* scripts and
# confirm the module loads and the active policy rebuilds.
set -ex

RPM_PATH="${1:?rpm path required}"

if command -v dnf >/dev/null 2>&1; then PM=dnf; else PM=yum; fi
"$PM" install -y setools-console policycoreutils-python-utils container-selinux "$RPM_PATH"

semodule -l | grep -q '^vcluster'
semodule -B
echo "PASS: module loaded and policy rebuilds cleanly"
