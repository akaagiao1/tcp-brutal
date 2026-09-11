#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/install.sh"
RULES_DIR=$(mktemp -d)
trap 'rm -rf "$RULES_DIR"' EXIT
setup_boot() { :; }
/usr/local/bin/brutalctl() {
  case "$1" in
    list) printf 'DESTINATION RATE\n223.80.170.224/32 50\n' ;;
    del) echo "$2" >> "$RULES_DIR/deleted" ;;
    add) echo "$2 $3" >> "$RULES_DIR/added" ;;
  esac
}
apply_rule 223.80.170.224/32 50
apply_rule 1.1.1.1/32 20
apply_rule 1.1.1.1/32 30
[[ $(wc -l < "$RULES_DIR/rules.conf") -eq 2 ]]
grep -qx '1.1.1.1/32 30' "$RULES_DIR/rules.conf"
delete_rule 223.80.170.224/32
grep -qx '223.80.170.224/32' "$RULES_DIR/deleted"
[[ $(cat "$RULES_DIR/rules.conf") == '1.1.1.1/32 30' ]]
# Saved-only deletion works even after reboot before restoration.
delete_rule 1.1.1.1/32
[[ ! -s $RULES_DIR/rules.conf ]]
[[ $(wc -l < "$RULES_DIR/deleted") -eq 1 ]]
save_rule 223.80.170.224/32 50
/usr/local/bin/brutalctl() {
  case "$1" in
    list) echo '223.80.170.224/32 50' ;;
    del) return 1 ;;
  esac
}
if delete_rule 223.80.170.224/32; then exit 1; fi
grep -qx '223.80.170.224/32 50' "$RULES_DIR/rules.conf"
if delete_rule '1.1.1.1;id'; then exit 1; fi
# Numbered deletion merges live and saved rules without duplicates.
printf '223.80.170.224/32 50\n198.51.100.0/24 30\n' > "$RULES_DIR/rules.conf"
/usr/local/bin/brutalctl() {
  case "$1" in
    list) printf 'DESTINATION RATE\n223.80.170.224/32 50\n192.0.2.0/24 20\n' ;;
    del) echo "$2" >> "$RULES_DIR/deleted-numbered" ;;
    flush) echo flush >> "$RULES_DIR/flushed" ;;
  esac
}
prompt_delete <<< '2'
grep -qx '192.0.2.0/24' "$RULES_DIR/deleted-numbered"
grep -qx '223.80.170.224/32 50' "$RULES_DIR/rules.conf"
grep -qx '198.51.100.0/24 30' "$RULES_DIR/rules.conf"
# Zero clears live and persistent rules.
prompt_delete <<< '0'
grep -qx flush "$RULES_DIR/flushed"
[[ ! -s $RULES_DIR/rules.conf ]]
# The direct delete command uses the same all-rules operation.
printf '203.0.113.0/24 10\n' > "$RULES_DIR/rules.conf"
delete_all_rules
[[ ! -s $RULES_DIR/rules.conf ]]
# The menu dispatches multiple operations, then exits without installing packages.
configure_rule() { echo menu-add; }
prompt_delete() { echo menu-delete; }
show_rules() { echo menu-list; }
result=$(rule_menu <<< $'1\n2\n3\n0')
[[ $result == *menu-add* && $result == *menu-delete* && $result == *menu-list* ]]
echo 'Rule management tests passed.'
