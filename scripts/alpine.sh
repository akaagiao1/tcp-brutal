#!/usr/bin/env bash
# Standalone Alpine installer: download pinned source, build and load Brutal.
set -euo pipefail
case "${1:-install}" in
  help|-h|--help)
    echo 'Usage: bash alpine.sh [install|uninstall]'
    exit 0 ;;
  install|uninstall) action=${1:-install} ;;
  *) echo 'Usage: bash alpine.sh [install|uninstall]' >&2; exit 2 ;;
esac
[[ $(uname -s) == Linux && -f /etc/alpine-release ]] || { echo 'Requires Alpine Linux.' >&2; exit 1; }
[[ $EUID == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
# Pin the module source so upstream changes cannot silently alter installation.
source_commit=377d2a0e9324ef585ff90ea91779baf276cf6a50
apk add --no-cache curl ca-certificates
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
curl -fL --retry 3 "https://github.com/akaagiao1/tcp-brutal/archive/$source_commit.tar.gz" -o "$scratch/source.tar.gz"
tar -xzf "$scratch/source.tar.gz" -C "$scratch"
src="$scratch/tcp-brutal-$source_commit"
# Use the installer shipped alongside this bootstrap when downloaded together.
# Otherwise retrieve it from the fork's default branch.
local_installer="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/install_alpine.sh"
if [[ -f $local_installer ]]; then
  cp "$local_installer" "$src/scripts/install_alpine.sh"
else
  curl -fL --retry 3 https://raw.githubusercontent.com/akaagiao1/tcp-brutal/master/scripts/install_alpine.sh -o "$src/scripts/install_alpine.sh"
fi
bash "$src/scripts/install_alpine.sh" "$action"
