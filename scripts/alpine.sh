#!/usr/bin/env bash
# Compatibility entry point; use the cross-distribution installer.
set -euo pipefail
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
curl -fL --retry 3 https://raw.githubusercontent.com/akaagiao1/tcp-brutal/master/scripts/install.sh -o "$scratch/install.sh"
bash "$scratch/install.sh" "$@"
