#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/install.sh"
RULES_DIR=$(mktemp -d)
trap 'rm -rf "$RULES_DIR"' EXIT
setup_boot() { :; }
save_rule 223.80.170.224 50
save_rule 1.1.1.1 20
save_rule 223.80.170.224 40
[[ $(wc -l < "$RULES_DIR/rules.conf") -eq 2 ]]
grep -qx '223.80.170.224 40' "$RULES_DIR/rules.conf"
modprobe() { :; }
/usr/local/bin/brutalctl() { printf '%s\n' "$*"; }
result=$(restore_rules)
[[ $result == *'add 223.80.170.224/32 40'* && $result == *'add 1.1.1.1/32 20'* ]]
echo 'bad-input 50' > "$RULES_DIR/rules.conf"
if restore_rules; then exit 1; fi
echo 'Rule save, replacement, restoration and validation tests passed.'
