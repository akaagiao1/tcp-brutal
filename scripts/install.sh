#!/usr/bin/env bash
# Cross-distribution installer: download pinned source, build and load Brutal.
set -euo pipefail
RULES_DIR=/etc/tcp-brutal
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
  apply_rule "$client_ip" "$rate"
}
apply_rule() {
  local client_ip=$1 rate=$2
  valid_ipv4 "$client_ip" && valid_rate "$rate" || { echo '无效的 IPv4 或 Mbps。' >&2; return 1; }
  if ! /usr/local/bin/brutalctl add "$client_ip/32" "$rate"; then
    echo '添加失败，可能只写入了部分规则；请检查以下状态。' >&2
    /usr/local/bin/brutalctl list || true
    return 1
  fi
  /usr/local/bin/brutalctl list || return 1
  echo "已设置 $client_ip/32，共享 $rate Mbps。请重新连接代理。"
  if save_rule "$client_ip" "$rate"; then
    echo '规则已保存，开机自动恢复。公网 IP 变化时请移除旧规则并重新配置。'
  else
    echo '当前规则已生效，但保存或开机配置失败，请检查错误后重试。' >&2
    return 1
  fi
}
prompt_configure() {
  [[ -x /usr/local/bin/brutalctl && -r /proc/net/tcp_brutal/rules ]] || {
    echo '工具或 v2 规则接口尚未就绪，未添加规则。' >&2
    return 1
  }
  if [[ -t 0 ]]; then
    rule_menu
  else
    echo '非交互运行，跳过规则填写。稍后执行 bash install.sh configure。'
  fi
}
show_rules() {
  echo '当前生效规则：'
  /usr/local/bin/brutalctl list || return 1
  echo '开机恢复规则（IPv4 Mbps）：'
  if [[ -s $RULES_DIR/rules.conf ]]; then cat "$RULES_DIR/rules.conf"; else echo '（无）'; fi
}
delete_rule() {
  local client_ip=$1 current tmp
  valid_ipv4 "$client_ip" || { echo '无效的 IPv4。' >&2; return 1; }
  current=$(/usr/local/bin/brutalctl list) || return 1
  # Prepare the saved file before changing live state. Preserve other entries.
  install -d -m 700 "$RULES_DIR" || return 1
  tmp=$(mktemp "$RULES_DIR/rules.XXXXXX") || return 1
  if [[ -f $RULES_DIR/rules.conf ]]; then
    awk -v ip="$client_ip" '$1 != ip' "$RULES_DIR/rules.conf" > "$tmp" || { rm -f "$tmp"; return 1; }
  fi
  if awk -v prefix="$client_ip/32" '$1 == prefix {found=1} END {exit !found}' <<< "$current"; then
    if ! /usr/local/bin/brutalctl del "$client_ip/32"; then
      rm -f "$tmp"
      echo '当前规则删除失败，保存的配置未修改。' >&2
      return 1
    fi
  fi
  chmod 600 "$tmp" && mv "$tmp" "$RULES_DIR/rules.conf" || {
    rm -f "$tmp"
    echo '保存文件更新失败，请检查，避免旧规则重启后恢复。' >&2
    return 1
  }
  echo "已移除 $client_ip 的当前及开机规则（若存在）。已有 TCP 连接可能继续使用旧参数，请重新连接。"
}
prompt_delete() {
  local client_ip
  show_rules || return 1
  read -r -p '要删除的客户端公网 IPv4（回车取消）：' client_ip || return 0
  [[ -n $client_ip ]] || return 0
  delete_rule "$client_ip"
}
rule_menu() {
  local choice
  while true; do
    printf '\n1) 添加公网 IP / 修改已有 IP 的带宽\n2) 删除公网 IP 和带宽规则\n3) 查看当前及开机规则\n0) 退出\n'
    read -r -p '请选择：' choice || return 0
    case "$choice" in
      1) configure_rule || echo '操作失败，请检查上面的错误。' ;;
      2) prompt_delete || echo '操作失败，请检查上面的错误。' ;;
      3) show_rules || echo '读取规则失败。' ;;
      0|'') return 0 ;;
      *) echo '请输入 0、1、2 或 3。' ;;
    esac
  done
}
detect_family() {
  case " $1 $2 " in
    *alpine*) echo alpine ;;
    *debian*|*ubuntu*) echo debian ;;
    *centos*|*rhel*|*rocky*|*almalinux*|*fedora*) echo rhel ;;
    *) return 1 ;;
  esac
}
packages() {
  case "$family" in
    alpine) apk add --no-cache "$@" ;;
    debian) DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    rhel) "$rpm_manager" install -y "$@" ;;
  esac
}
install_tools() {
  case "$family" in
    alpine) packages build-base iproute2 kmod ;;
    debian) packages build-essential iproute2 kmod ;;
    rhel) packages gcc make glibc-devel iproute kmod ;;
  esac
  make -C "$src/tools" clean
  make -C "$src/tools"
  install -d /usr/local/bin
  install -m 755 "$src/tools/brutalctl" /usr/local/bin/brutalctl
}
install_module() {
  local kernel build
  kernel=$(uname -r)
  build="/lib/modules/$kernel/build"
  case "$family" in
    alpine)
      if [[ ! -f $build/Makefile ]]; then
        case "$kernel" in
          *-virt) packages linux-virt-dev ;;
          *-lts) packages linux-lts-dev ;;
          *) echo 'Install development files for your custom kernel.' >&2; return 1 ;;
        esac
      fi ;;
    debian) packages "linux-headers-$kernel" libelf-dev ;;
    rhel) packages "kernel-devel-$kernel" elfutils-libelf-devel ;;
  esac
  [[ -f $build/Makefile && -f $build/include/config/kernel.release ]] || {
    echo "No matching development files for $kernel. Update kernel and headers together, reboot, then retry." >&2; return 1;
  }
  [[ $(cat "$build/include/config/kernel.release") == "$kernel" ]] || {
    echo 'Kernel development version mismatch; do not create fake symlinks.' >&2; return 1;
  }
  make -C "$src" KERNEL_DIR="$build" clean
  (cd "$src" && make KERNEL_DIR="$build")
  [[ $(modinfo -F vermagic "$src/brutal.ko" | cut -d ' ' -f 1) == "$kernel" ]] || return 1
  install -d "/lib/modules/$kernel/extra"
  install -m 644 "$src/brutal.ko" "/lib/modules/$kernel/extra/brutal.ko"
  depmod -a "$kernel"
  modprobe brutal
  install -d /etc/modules-load.d
  echo brutal > /etc/modules-load.d/brutal.conf
  echo 'Module installed. After a kernel upgrade, rerun installation for the new kernel.'
}
restore_rules() {
  local ip rate extra
  modprobe brutal || return 1
  [[ -f $RULES_DIR/rules.conf ]] || return 0
  while read -r ip rate extra; do
    [[ -n $ip ]] || continue
    valid_ipv4 "$ip" && valid_rate "$rate" && [[ -z $extra ]] || return 1
    /usr/local/bin/brutalctl add "$ip/32" "$rate" || return 1
  done < $RULES_DIR/rules.conf
}
setup_boot() {
  install -d /usr/local/libexec || return 1
  install -m 755 "${BASH_SOURCE[0]}" /usr/local/libexec/tcp-brutal-manager || return 1
  if [[ $family == alpine ]]; then
    command -v rc-update >/dev/null || { echo 'OpenRC is required for boot restoration.' >&2; return 1; }
    cat > /etc/init.d/tcp-brutal-rules <<'RC'
#!/sbin/openrc-run
name="TCP Brutal rules"
depend() { need net; after modules; }
start() {
  ebegin "Restoring TCP Brutal rules"
  /bin/bash /usr/local/libexec/tcp-brutal-manager restore
  eend $?
}
RC
    chmod 755 /etc/init.d/tcp-brutal-rules
    rc-update add tcp-brutal-rules default
  else
    [[ -d /run/systemd/system ]] || { echo 'A running systemd system is required for boot restoration.' >&2; return 1; }
    cat > /etc/systemd/system/tcp-brutal-rules.service <<'UNIT'
[Unit]
Description=Restore TCP Brutal bandwidth rules
Wants=network-online.target
After=network-online.target systemd-modules-load.service
StartLimitIntervalSec=0
[Service]
Type=oneshot
ExecStart=/bin/bash /usr/local/libexec/tcp-brutal-manager restore
RemainAfterExit=yes
Restart=on-failure
RestartSec=15
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable tcp-brutal-rules.service
  fi
}
save_rule() {
  local ip=$1 rate=$2 tmp
  setup_boot || return 1
  install -d -m 700 "$RULES_DIR" || return 1
  tmp=$(mktemp "$RULES_DIR/rules.XXXXXX") || return 1
  if [[ -f $RULES_DIR/rules.conf ]]; then
    awk -v ip="$ip" '$1 != ip' "$RULES_DIR/rules.conf" > "$tmp" || { rm -f "$tmp"; return 1; }
  fi
  printf '%s %s\n' "$ip" "$rate" >> "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" && mv "$tmp" "$RULES_DIR/rules.conf" || { rm -f "$tmp"; return 1; }
}
main() {
  local action=${1:-auto} family rpm_manager kernel major rest minor
  case "$action" in
    help|-h|--help) echo 'Usage: bash install.sh [install|tools|configure|menu|list|add IP Mbps|delete IP|restore]'; return ;;
    auto|install|tools|configure|menu|list|add|delete|restore) ;;
    *) echo 'Unknown action. Use --help.' >&2; return 2 ;;
  esac
  [[ $(uname -s) == Linux && $EUID == 0 ]] || { echo 'Run as root on Linux.' >&2; return 1; }
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  . /etc/os-release
  family=$(detect_family "$ID" "${ID_LIKE:-}") || { echo 'Unsupported distribution.' >&2; return 1; }
  if [[ $action == auto ]]; then
    if [[ -x /usr/local/bin/brutalctl && -r /proc/net/tcp_brutal/rules ]]; then action=menu; else action=install; fi
  fi
  case "$action" in
    add) [[ $# == 3 ]] || { echo 'Usage: bash install.sh add IP Mbps'; return 2; }; apply_rule "$2" "$3"; return ;;
    delete) [[ $# == 2 ]] || { echo 'Usage: bash install.sh delete IP'; return 2; }; delete_rule "$2"; return ;;
    list) show_rules; return ;;
    menu) prompt_configure; return ;;
  esac
  if [[ $action == restore ]]; then restore_rules; return; fi
  if [[ $action == configure ]]; then prompt_configure; return; fi
  kernel=$(uname -r); major=${kernel%%.*}; rest=${kernel#*.}; minor=${rest%%.*}
  (( major > 5 || (major == 5 && minor >= 10) )) || {
    echo 'TCP Brutal v2 requires Linux >= 5.10. Stock CentOS 7/8 kernels are too old; upgrade the OS/kernel first.' >&2; return 1;
  }
  case "$family" in
    debian) apt-get update ;;
    rhel) rpm_manager=$(command -v dnf || command -v yum) ;;
  esac
  packages curl ca-certificates tar gzip
  scratch=$(mktemp -d)
  trap 'rm -rf "$scratch"' EXIT
  local commit=377d2a0e9324ef585ff90ea91779baf276cf6a50
  curl -fL --retry 3 "https://github.com/akaagiao1/tcp-brutal/archive/$commit.tar.gz" -o "$scratch/source.tar.gz"
  tar -xzf "$scratch/source.tar.gz" -C "$scratch"
  src="$scratch/tcp-brutal-$commit"
  install_tools
  if [[ $action == install ]]; then
    if [[ -r /sys/module/brutal/version ]]; then
      [[ $(cat /sys/module/brutal/version) == 2.* ]] || { echo 'Unload the older module before installing v2.' >&2; return 1; }
      echo 'Brutal v2 is already loaded; tools repaired.'
    else
      install_module
    fi
  fi
  prompt_configure
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
