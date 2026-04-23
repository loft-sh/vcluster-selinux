#!/usr/bin/env bash
# Static analysis of the policy sources: selint across .te/.if/.fc and
# sepolgen-ifgen for interface syntax (checkmodule doesn't parse .if).
set -euo pipefail

# selint ships in Fedora; EL needs a source build (autotools, trivial).
if ! command -v selint >/dev/null 2>&1; then
  if ! dnf install -y selint >/dev/null 2>&1; then
    dnf install -y --setopt=install_weak_deps=False \
      gcc make autoconf automake libtool bison flex check-devel pkgconf-pkg-config git
    git clone --depth=1 https://github.com/SELinuxProject/selint /tmp/selint
    ( cd /tmp/selint && ./autogen.sh && ./configure && make && make install )
  fi
fi
dnf install -y policycoreutils-devel selinux-policy-devel

# el8 and el9 .te/.if/.fc are byte-identical (enforced by verify-consistency);
# lint el9 only. -F makes selint exit nonzero on any remaining finding.
selint -F -c test/selint.conf --recursive policy/el9/

sepolgen-ifgen -i policy/el9/vcluster.if -o /tmp/ifinfo.el9

echo "PASS: selint + sepolgen-ifgen"
