#!/usr/bin/env bash
set -euo pipefail

working_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd -P)"
root_dir="${working_dir}/.."
lib="${root_dir}/lib/ufw-docker-rules.sh"
cli="${root_dir}/ufw-docker-rulectl"

bash -n "$lib"
bash -n "$cli"

# shellcheck disable=SC1090
source "$lib"

ufw_docker_parse_comment "allow nginx 80/tcp frontend"
[[ "$UFW_DOCKER_RULE_INSTANCE" == "nginx" ]]
[[ "$UFW_DOCKER_RULE_PORT" == "80" ]]
[[ "$UFW_DOCKER_RULE_PROTO" == "tcp" ]]
[[ "$UFW_DOCKER_RULE_NETWORK" == "frontend" ]]
[[ -z "$UFW_DOCKER_RULE_SOURCE" ]]
[[ "$UFW_DOCKER_RULE_IS_V6" == "0" ]]

ufw_docker_parse_comment "allow nginx/v6 80/tcp frontend from:2001:db8::/64"
[[ "$UFW_DOCKER_RULE_INSTANCE" == "nginx" ]]
[[ "$UFW_DOCKER_RULE_SOURCE" == "2001:db8::/64" ]]
[[ "$UFW_DOCKER_RULE_IS_V6" == "1" ]]
[[ "$(ufw_docker_rule_key)" == "nginx|80|tcp|frontend|2001:db8::/64" ]]

ufw_docker_managed_status_lines() {
    cat <<'EOF'
[ 1] 172.18.0.3 80/tcp ALLOW FWD Anywhere # allow nginx 80/tcp frontend
[ 2] fd00::3 80/tcp (v6) ALLOW FWD Anywhere (v6) # allow nginx/v6 80/tcp frontend
[ 3] 172.18.0.3 443/tcp ALLOW FWD 192.0.2.0/24 # allow nginx 443/tcp frontend from:192.0.2.0/24
[ 4] 172.19.0.4 53/udp ALLOW FWD Anywhere # allow dns 53/udp backend
EOF
}

text="$(ufw_docker_list_rules nginx 80/tcp frontend '' text)"
[[ "$text" == *"[ 1]"* ]]
[[ "$text" == *"[ 2]"* ]]
[[ "$text" != *"[ 3]"* ]]

tsv="$(ufw_docker_list_rules nginx 443/tcp frontend 192.0.2.0/24 tsv)"
[[ "$tsv" == *$'number\tcontainer\tport\tproto\tnetwork\tsource\tipv6'* ]]
[[ "$tsv" == *$'3\tnginx\t443\ttcp\tfrontend\t192.0.2.0/24\t0'* ]]

numbers="$(ufw_docker_collect_rule_numbers nginx '' '' '')"
[[ "$numbers" == *"1"* ]]
[[ "$numbers" == *"2"* ]]
[[ "$numbers" == *"3"* ]]
[[ "$numbers" != *"4"* ]]

delete_output="$(ufw_docker_delete_rules nginx 443/tcp frontend 192.0.2.0/24 1)"
[[ "$delete_output" == *'delete "3"'* ]]
[[ "$delete_output" == *"ufw delete 3"* ]]

reload_output="$(ufw_docker_reload_rules /bin/echo 1)"
# IPv4/v6 copies of the same ordinary rule are deduplicated.
[[ "$(grep -c 'nginx 80/tcp frontend' <<< "$reload_output")" -eq 1 ]]
[[ "$reload_output" == *"allow-ip"* ]]
[[ "$reload_output" == *"192.0.2.0/24"* ]]

parse_output="$(printf '%s\n' 'allow nginx/v6 80/tcp frontend from:2001:db8::/64' | bash "$cli" parse)"
[[ "$parse_output" == *$'nginx\t80\ttcp\tfrontend\t2001:db8::/64\t1'* ]]

printf 'ufw-docker-rulectl tests passed\n'
