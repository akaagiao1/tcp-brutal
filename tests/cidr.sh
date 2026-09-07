#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/install.sh"
[[ $(normalize_prefix 223.80.170.224) == 223.80.170.0/24 ]]
[[ $(normalize_saved_prefix 223.80.170.224) == 223.80.170.224/32 ]]
[[ $(normalize_prefix 223.80.170.224/24) == 223.80.170.0/24 ]]
[[ $(normalize_prefix 223.80.170.224/16) == 223.80.0.0/16 ]]
[[ $(normalize_prefix 223.80.170.224/0) == 0.0.0.0/0 ]]
[[ $(normalize_prefix 255.255.255.255/32) == 255.255.255.255/32 ]]
[[ $(normalize_prefix 192.0.2.3/31) == 192.0.2.2/31 ]]
for invalid in '1.2.3.4/33' '1.2.3.4/-1' '1.2.3.4/024' '1.2.3.4/24/1' '1.2.3.4/' '1.2.3.4/a'; do
  if normalize_prefix "$invalid"; then exit 1; fi
done
RULES_DIR=$(mktemp -d)
trap 'rm -rf "$RULES_DIR"' EXIT
setup_boot() { :; }
modprobe() { :; }
/usr/local/bin/brutalctl() {
  if [[ $1 == list ]]; then echo '223.80.170.0/24 50'; else echo "$*" >> "$RULES_DIR/commands"; fi
}
echo '223.80.170.224 50' > "$RULES_DIR/rules.conf"
save_rule 223.80.170.224/32 40
[[ $(cat "$RULES_DIR/rules.conf") == '223.80.170.224/32 40' ]]
apply_rule 223.80.170.224/24 50
apply_rule 223.80.170.1/24 30
[[ $(wc -l < "$RULES_DIR/rules.conf") -eq 2 ]]
grep -qx '223.80.170.0/24 30' "$RULES_DIR/rules.conf"
restore_rules
grep -qx 'add 223.80.170.0/24 30' "$RULES_DIR/commands"
delete_rule 223.80.170.99/24
[[ $(cat "$RULES_DIR/rules.conf") == '223.80.170.224/32 40' ]]
grep -qx 'del 223.80.170.0/24' "$RULES_DIR/commands"
echo 'CIDR normalization, update, restore and deletion passed.'
