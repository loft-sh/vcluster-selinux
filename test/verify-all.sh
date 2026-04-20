#!/usr/bin/env bash
# End-to-end RPM verification: install, contexts, rules, uninstall.
set -euo pipefail

RPM_PATH="${1:?rpm path required}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$HERE/verify-install.sh"        "$RPM_PATH"
"$HERE/verify-contexts.sh"
"$HERE/verify-rules-positive.sh"
"$HERE/verify-rules-negative.sh"
"$HERE/verify-uninstall.sh"
