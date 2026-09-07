#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/install.sh"
for ip in 223.80.170.224 1.1.1.1 255.255.255.255; do valid_ipv4 "$ip"; done
for ip in '' '1.2.3' '256.1.1.1' '01.2.3.4' '1.2.3.4/32' '1.2.3.4;id' '-1.2.3.4'; do
  if valid_ipv4 "$ip"; then echo "Unexpected valid IP: $ip"; exit 1; fi
done
for rate in 1 50 1000000; do valid_rate "$rate"; done
for rate in 0 -1 50M 01 1000001 999999999999999999999999; do
  if valid_rate "$rate"; then echo "Unexpected valid rate: $rate"; exit 1; fi
done
# Mock only the command, so no route or host configuration is changed.
/usr/local/bin/brutalctl() {
  if [[ $1 == add ]]; then
    [[ $2 == 223.80.170.224/32 && $3 == 50 ]] || return 1
    echo 'MOCK_ADDED'
  fi
}
save_rule() { :; }
result=$(configure_rule <<< $'invalid\n223.80.170.224\n0\n50')
[[ $result == *MOCK_ADDED* ]]
result=$(configure_rule <<< '')
[[ $result != *MOCK_ADDED* ]]
/usr/local/bin/brutalctl() { return 1; }
if configure_rule <<< $'223.80.170.224\n50'; then exit 1; fi
echo 'Alpine input and rule flow tests passed.'

[[ $(detect_family debian '') == debian ]]
[[ $(detect_family ubuntu debian) == debian ]]
[[ $(detect_family centos 'rhel fedora') == rhel ]]
[[ $(detect_family rocky 'rhel centos fedora') == rhel ]]
[[ $(detect_family alpine '') == alpine ]]
if detect_family unknown ''; then exit 1; fi
