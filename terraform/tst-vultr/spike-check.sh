#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
First sign in to op (freecodecamp.1password.com), then join the tailnet,
from ansible/ (again after each re-create):
  ansible-playbook -i inventory/vultr.yml -i inventory/constructed.yml \
    play-tailscale--0-install.yml -e variable_host=tst_pxy:tst_mgr:tst_wkr
  ansible-playbook -i inventory/vultr.yml -i inventory/constructed.yml \
    play-tailscale--1a-up.yml \
    -e variable_host=tst_pxy:tst_mgr:tst_wkr -e variable_ssh=false \
    -e variable_tags=tag:added-by-ops,tag:deployment-tgt
Then log in on the Vultr web console of each VM, and from the repo root run:
  SNAPSHOT_ID=<ID of the last apply> CONSOLE_LOGIN_OK=yes direnv exec terraform/tst-vultr terraform/tst-vultr/spike-check.sh
EOF
  exit 2
}

dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$dir/../.." && pwd)
fails=0
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

nodes=$(tofu -chdir="$dir" output -json nodes 2>/dev/null) || usage
vpc_cidr=$(tofu -chdir="$dir" output -raw vpc_cidr 2>/dev/null) || usage
team_keys=$(tofu -chdir="$dir" output -json team_keys 2>/dev/null | jq -r '.[]') || usage
[ -n "${VULTR_API_KEY:-}" ] || usage
[ -n "${SNAPSHOT_ID:-}" ] || usage
names=$(printf '%s' "$nodes" | jq -r 'keys[]')
vpc_gateway=$(printf '%s' "$vpc_cidr" | sed 's#\.0/[0-9]*$#.1#')

ip_int() {
  local a b c d
  IFS=. read -r a b c d <<<"$1"
  echo $(((a << 24) + (b << 16) + (c << 8) + d))
}

in_vpc() {
  local bits=${vpc_cidr#*/}
  local mask=$(((0xffffffff << (32 - bits)) & 0xffffffff))
  [ $(($(ip_int "$1") & mask)) -eq $(($(ip_int "${vpc_cidr%/*}") & mask)) ]
}

report() {
  printf '%s %s%s\n' "$1" "$2" "${3:+ ($3)}"
  [ "$1" = PASS ] || fails=$((fails + 1))
}

check() {
  name=$1
  shift
  if "$@" >/dev/null 2>&1; then report PASS "$name"; else report FAIL "$name"; fi
}

field() {
  printf '%s' "$nodes" | jq -r --arg n "$1" --arg f "$2" '.[$n][$f]'
}

by_role() {
  printf '%s' "$nodes" | jq -r --arg r "$1" 'to_entries[] | select(.value.role == $r) | .key'
}

on() {
  host=$1
  shift
  # shellcheck disable=SC2029
  ssh "${ssh_opts[@]}" "freecodecamp@$(field "$host" main_ip)" "$@"
}

vpc_ip() {
  local src
  src=$(on "$1" "ip -4 route get $vpc_gateway" | sed -n 's/.* src \([0-9.]*\).*/\1/p')
  [ -n "$src" ] && in_vpc "$src" && printf '%s\n' "$src"
}

times_out() {
  local rc=0
  curl -s -o /dev/null --connect-timeout 5 "http://$1:$2/" || rc=$?
  [ "$rc" -eq 28 ]
}

same_names() {
  local label
  label=$(curl -fsS -H "Authorization: Bearer $VULTR_API_KEY" \
    "https://api.vultr.com/v2/instances/$(field "$1" id)" | jq -r '.instance.label')
  [ "$label" = "$1" ] && [ "$(on "$1" hostname)" = "$1" ]
}

one_tailnet_name() {
  tailscale status --json | jq -e --arg n "$1" '
    [.Peer[] | {label: (.DNSName | split(".")[0]), online: .Online}] as $peers
    | ([$peers[] | select(.label == $n and .online)] | length == 1)
      and ([$peers[] | select(.label | startswith($n + "-"))] | length == 0)'
}

has_team_keys() {
  keys=$(on "$1" cat .ssh/authorized_keys) || return 1
  printf '%s\n' "$team_keys" | while IFS= read -r key; do
    printf '%s\n' "$keys" | grep -qxF "$key" || exit 1
  done
}

sshd_hardened() {
  config=$(on "$1" sudo sshd -T) || return 1
  for line in "passwordauthentication no" "permitrootlogin no" \
    "pubkeyauthentication yes" "allowusers freecodecamp"; do
    printf '%s\n' "$config" | grep -qx "$line" || return 1
  done
}

listen() {
  on "$1" "sudo systemctl reset-failed spike-http-$2 2>/dev/null;
    sudo systemd-run --collect --unit=spike-http-$2 python3 -m http.server $2 &&
    sleep 2 && ss -Hltn sport = :$2 | grep -q LISTEN"
}

answers_in_vpc() {
  on "$1" "nc -z -w 5 $2 $3"
}

swarm_nodes_ready() {
  expected=$(printf '%s\n' "$(by_role mgr)" "$(by_role wkr)" | sort | sed 's/$/ Ready/')
  actual=$(on "$1" "sudo docker node ls --format '{{.Hostname}} {{.Status}}'" | sort)
  [ "$actual" = "$expected" ]
}

swarm_play_idempotent() {
  recap=$(cd "$root/ansible" && ansible-playbook -i inventory/vultr.yml \
    -i inventory/constructed.yml play-swarm--form.yml \
    -e swarm_manager_group=tst_mgr -e swarm_worker_group=tst_wkr) || return 1
  printf '%s\n' "$recap" | grep -q 'changed=' || return 1
  ! printf '%s\n' "$recap" | grep -E 'changed=[1-9]'
}

in_inventory_group() {
  (cd "$root/ansible" && ansible-inventory -i inventory/vultr.yml \
    -i inventory/constructed.yml --graph "tst_$2") |
    grep -qE -- "--$1\$"
}

plan_clean() {
  tofu -chdir="$dir" plan -detailed-exitcode -input=false -var snapshot_id="$SNAPSHOT_ID"
}

state_encrypted() {
  [ -n "${AWS_ENDPOINT_URL_S3:-}" ] || return 1
  rclone cat ":s3:infra-tfstate/tst-vultr/terraform.tfstate" --s3-provider Cloudflare \
    --s3-env-auth --s3-endpoint "$AWS_ENDPOINT_URL_S3" |
    jq -e 'has("encrypted_data") and (has("resources") | not)'
}

for n in $names; do
  check "boot $n" on "$n" true
  check "label = hostname $n" same_names "$n"
  check "tailnet name $n" one_tailnet_name "$n"
  check "team keys $n" has_team_keys "$n"
  check "sshd hardened $n" sshd_hardened "$n"
  check "fail2ban active $n" on "$n" systemctl is-active --quiet fail2ban
  check "inventory tst_$(field "$n" role) $n" in_inventory_group "$n" "$(field "$n" role)"
done

if [ "${CONSOLE_LOGIN_OK:-}" = yes ]; then
  report PASS "web console login"
else
  report FAIL "web console login" "log in on each VM console, then set CONSOLE_LOGIN_OK=yes"
fi

mgr=$(by_role mgr)
wkr=$(by_role wkr)
mgr_vpc=$(vpc_ip "$mgr") || mgr_vpc=unknown

for pxy in $(by_role pxy); do
  pxy_vpc=$(vpc_ip "$pxy") || pxy_vpc=unknown
  for port in 80 443; do
    check "$port listener up $pxy" listen "$pxy" "$port"
    check "$port times out from the internet $pxy" times_out "$(field "$pxy" main_ip)" "$port"
    check "$port answers in the VPC $pxy" answers_in_vpc "$mgr" "$pxy_vpc" "$port"
  done
  on "$pxy" sudo systemctl stop spike-http-80 spike-http-443 >/dev/null 2>&1 || true
done

for port in 2377 7946; do
  check "swarm $port times out from the internet" times_out "$(field "$mgr" main_ip)" "$port"
  check "swarm $port answers in the VPC" answers_in_vpc "$wkr" "$mgr_vpc" "$port"
done

check "swarm nodes ready, none stale" swarm_nodes_ready "$mgr"
check "swarm play second run unchanged" swarm_play_idempotent
check "second tofu plan unchanged" plan_clean
check "R2 state encrypted" state_encrypted

printf '%s checks failed\n' "$fails"
[ "$fails" -eq 0 ]
