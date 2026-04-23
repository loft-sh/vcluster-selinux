#!/usr/bin/env bash
set -euo pipefail

if ! command -v createrepo_c >/dev/null 2>&1; then
  echo "createrepo_c is required to generate RPM repository metadata" >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <repo-dir> [<repo-dir>...]" >&2
  exit 1
fi

for repo_dir in "$@"; do
  if [[ ! -d "$repo_dir" ]]; then
    echo "repository directory not found: $repo_dir" >&2
    exit 1
  fi

  shopt -s nullglob
  rpms=("$repo_dir"/*.rpm)
  shopt -u nullglob
  if [[ ${#rpms[@]} -eq 0 ]]; then
    echo "no RPMs found in $repo_dir" >&2
    exit 1
  fi

  rm -rf "$repo_dir/repodata"
  createrepo_c "$repo_dir"
done
