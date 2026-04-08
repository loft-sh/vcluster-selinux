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

## Installing

Download the RPM for your distro from the GitHub release and install:

```bash
sudo dnf install ./vcluster-selinux-*.noarch.rpm
```

## Development

### Prerequisites

- Docker with buildx support
- GNU Make

### Building locally

```bash
# Build RPMs for all distros
make all

# Build a specific distro
make build-el9
make build-el8

# Output lands in dist/
ls dist/el9/noarch/*.rpm
```

Builds run inside Docker containers (Rocky Linux / CentOS Stream) so you don't need any RPM tooling installed locally.

### How the build works

1. `make build-el9` runs `docker buildx build` with `Dockerfile.el9`
2. Inside the container:
   - Installs `selinux-policy-devel`, `container-selinux`, `rpm-build`
   - Compiles `.te` + `.fc` + `.if` into a binary policy module (`.pp`)
   - `rpmbuild -ba` packages it into `.noarch.rpm` and `.src.rpm`
3. Output is exported to `dist/` via Docker's `--output` flag

### Modifying policies

Edit the policy files under `policy/el9/` (or `el8/`):

- `vcluster.te` -- type enforcement rules (what processes can do)
- `vcluster.fc` -- file contexts (which paths get which SELinux labels)
- `vcluster.if` -- interfaces (reusable macros for other policy modules)

Run `make build-el9` to verify the policy compiles. Push a PR to validate both distros in CI.

### Adding a new distro

1. Create `policy/<distro>/` with scripts, spec, and policy files
2. Create `Dockerfile.<distro>` with the appropriate base image
3. `make build-<distro>` picks it up automatically via the Makefile
