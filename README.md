# vcluster-selinux

SELinux policy RPM for [vCluster](https://github.com/loft-sh/vcluster) virtual Kubernetes clusters.

## Structure

```
policy/
  el8/          # RHEL 8 / Rocky 8 / Alma 8
  el9/          # RHEL 9 / Rocky 9 / Alma 9
    vcluster.te           # Type enforcement policy
    vcluster.fc           # File contexts
    vcluster.if           # Interfaces
    vcluster-selinux.spec # RPM spec
    scripts/
      entry               # Script dispatcher
      build               # Compile policy + build RPM
      sign                # GPG sign RPMs
      version             # Tag → version extraction
```

## Building

```bash
# Build all distros
make all

# Build a specific distro
make build-el9
```

Builds run inside Docker containers (Rocky Linux) for reproducibility.

## Releasing

1. Tag: `git tag v0.1.stable.1`
2. Push: `git push origin v0.1.stable.1`
3. Create a GitHub release from the tag
4. CI builds RPMs for all distros and uploads them as release assets

Tag format: `v{version}.{channel}.{release}` (e.g., `v0.1.stable.1`)

## Installing

Download the RPM for your distro from the GitHub release and install:

```bash
sudo dnf install ./vcluster-selinux-*.noarch.rpm
```
