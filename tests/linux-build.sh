#!/usr/bin/env bash
set -euo pipefail
source scripts/install.sh
. /etc/os-release
family=$(detect_family "$ID" "${ID_LIKE:-}")
src=/src
case "$family" in
  debian) apt-get update ;;
  rhel) rpm_manager=dnf ;;
esac
install_tools
bash tests/alpine-inputs.sh
bash tests/persistence.sh
case "$family" in
  alpine) packages linux-virt-dev ;;
  debian) packages linux-headers-amd64 libelf-dev ;;
  rhel) packages kernel-devel elfutils-libelf-devel ;;
esac
for build in /lib/modules/*/build /usr/src/kernels/*; do
  [[ -f $build/Makefile ]] || continue
  make KERNEL_DIR="$build" clean
  make KERNEL_DIR="$build"
  test -s brutal.ko
  modinfo ./brutal.ko
  exit 0
done
echo 'No prepared kernel development tree.' >&2
exit 1
