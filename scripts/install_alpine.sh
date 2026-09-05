#!/bin/sh
# Build the checked-out sources for the running Alpine kernel.
set -eu
fail() { printf '%s\n' "Error: $*" >&2; exit 1; }
case "${1:-install}" in
  -h|--help|help) echo "Usage: sh scripts/install_alpine.sh [install|uninstall]"; exit 0 ;;
  install|uninstall) action=${1:-install} ;;
  *) fail "Unknown action: $1" ;;
esac
[ "$(uname -s)" = Linux ] && [ -f /etc/alpine-release ] || fail 'Alpine Linux is required.'
[ "$(id -u)" = 0 ] || fail 'Run as root.'
kernel=$(uname -r)
module_dir="/lib/modules/$kernel/extra"
autoload=/etc/modules-load.d/brutal.conf
if [ "$action" = uninstall ]; then
  if lsmod | awk '$1 == "brutal" { found=1 } END { exit !found }'; then
    rmmod brutal || fail 'Module is in use; stop applications using Brutal and retry.'
  fi
  rm -f "$module_dir/brutal.ko" "$autoload"
  depmod -a "$kernel"
  echo 'Removed Brutal for the running kernel. Modules for other kernels are unchanged.'
  exit 0
fi
src=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ -f "$src/brutal.h" ] || fail 'Run this script from the complete source checkout.'
major=${kernel%%.*}
rest=${kernel#*.}
minor=${rest%%.*}
[ "$major" -gt 5 ] || { [ "$major" -eq 5 ] && [ "$minor" -ge 10 ]; } || fail 'This source version requires Linux 5.10 or newer.'
apk add --no-cache build-base kmod
build="/lib/modules/$kernel/build"
if [ ! -f "$build/Makefile" ]; then
  case "$kernel" in
    *-lts) apk add --no-cache linux-lts-dev ;;
    *-virt) apk add --no-cache linux-virt-dev ;;
    *) fail "Install matching development files for custom kernel $kernel first." ;;
  esac
fi
[ -f "$build/Makefile" ] || fail "No headers for running kernel $kernel. For this kernel flavor, run: apk upgrade linux-${kernel##*-} linux-${kernel##*-}-dev ; then reboot and rerun the installer. Do not symlink mismatched headers."
[ -f "$build/include/config/kernel.release" ] || fail 'Kernel build tree is not prepared.'
[ "$(cat "$build/include/config/kernel.release")" = "$kernel" ] || fail 'Kernel development files do not match the running kernel.'
cd "$src"
make KERNEL_DIR="$build" clean
make KERNEL_DIR="$build"
[ "$(modinfo -F vermagic ./brutal.ko | cut -d ' ' -f 1)" = "$kernel" ] || fail 'Built module vermagic does not match.'
# Never unload a module used by existing connections automatically.
if lsmod | awk '$1 == "brutal" { found=1 } END { exit !found }'; then
  fail 'Brutal is already loaded. Stop applications using it, run rmmod brutal, then retry.'
fi
mkdir -p "$module_dir"
install -m 644 brutal.ko "$module_dir/brutal.ko"
depmod -a "$kernel"
modprobe brutal
mkdir -p /etc/modules-load.d
printf 'brutal\n' > "$autoload"
if command -v rc-update >/dev/null 2>&1; then
  rc-update add modules boot
fi
echo "Installed and loaded Brutal for $kernel. Re-run after each kernel upgrade and reboot."
