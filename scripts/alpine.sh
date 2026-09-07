#!/usr/bin/env bash
# Standalone Alpine installer: download pinned source, build and load Brutal.
set -euo pipefail
valid_ipv4() {
  local value=$1 octet
  local -a parts
  [[ $value =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  IFS=. read -r -a parts <<< "$value"
  for octet in "${parts[@]}"; do
    [[ ${#octet} -le 3 && ( $octet == 0 || $octet != 0* ) ]] || return 1
    (( 10#$octet <= 255 )) || return 1
  done
}
valid_rate() {
  [[ $1 =~ ^[1-9][0-9]{0,6}$ ]] && (( 10#$1 <= 1000000 ))
}
configure_rule() {
  local client_ip rate
  echo '配置 TCP Brutal：填写客户端本地网络的公网 IPv4，不是 VPS IP。'
  while true; do
    read -r -p '客户端公网 IPv4（回车跳过）：' client_ip || return 0
    [[ -n $client_ip ]] || return 0
    valid_ipv4 "$client_ip" && break
    echo 'IPv4 格式错误，请输入四段 0–255 的数字，不带端口或掩码。'
  done
  while true; do
    read -r -p '带宽 Mbps（1–1000000 整数，按实际可用带宽填写；回车取消）：' rate || return 0
    [[ -n $rate ]] || return 0
    valid_rate "$rate" && break
    echo '请输入有效的正整数，例如 50 表示 50 Mbps。'
  done
  if ! /usr/local/bin/brutalctl add "$client_ip/32" "$rate"; then
    echo '添加失败，可能只写入了部分规则；请检查以下状态。' >&2
    /usr/local/bin/brutalctl list || true
    return 1
  fi
  /usr/local/bin/brutalctl list || return 1
  echo "已设置 $client_ip/32，共享 $rate Mbps。请重新连接代理。"
  echo '规则重启后不会保留；公网 IP 变化后需删除旧规则再添加新规则。'
}
prompt_configure() {
  [[ -x /usr/local/bin/brutalctl && -r /proc/net/tcp_brutal/rules ]] || {
    echo '工具或 v2 规则接口尚未就绪，未添加规则。' >&2
    return 1
  }
  if [[ -t 0 ]]; then
    configure_rule
  else
    echo '非交互运行，跳过规则填写。稍后执行 bash alpine.sh configure。'
  fi
}
main() {
case "${1:-install}" in
  help|-h|--help)
    echo 'Usage: bash alpine.sh [install|tools|configure|uninstall]'
    exit 0 ;;
  install|tools|configure|uninstall) action=${1:-install} ;;
  *) echo 'Usage: bash alpine.sh [install|tools|configure|uninstall]' >&2; exit 2 ;;
esac
[[ $(uname -s) == Linux && -f /etc/alpine-release ]] || { echo 'Requires Alpine Linux.' >&2; exit 1; }
[[ $EUID == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
if [[ $action == configure ]]; then
  prompt_configure
  return
fi
if [[ $action == install && -r /sys/module/brutal/version ]]; then
  case "$(cat /sys/module/brutal/version)" in
    2.*) echo '检测到 Brutal v2 已加载，补装管理工具后配置规则。'; action=tools ;;
  esac
fi
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

if [[ $action != uninstall ]]; then
  prompt_configure
fi
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
