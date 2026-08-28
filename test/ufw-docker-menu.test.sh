#!/usr/bin/env bash
set -euo pipefail

working_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd -P)"
root_dir="${working_dir}/.."
menu="${root_dir}/ufw-docker-menu"
modules="${root_dir}/lib/ufw-docker-menu"

bash -n "$menu"
for module in "$modules"/*.sh; do
    bash -n "$module"
done

export NO_COLOR=1
export UFW_DOCKER_MENU_TESTING=1
export UFW_DOCKER_MENU_NO_PYTHON=1
# shellcheck disable=SC1090
source "$menu"

validate_port_proto ""
validate_port_proto "443/tcp"
validate_port_proto "53/udp"
! validate_port_proto "80"
! validate_port_proto "70000/tcp"
! validate_port_proto "80/sctp"

validate_ip_or_cidr "1.2.3.4"
validate_ip_or_cidr "10.0.0.0/8"
validate_ip_or_cidr "2001:db8::1"
validate_ip_or_cidr "2001:db8::/64"
! validate_ip_or_cidr ""
! validate_ip_or_cidr "999.1.2.3"
! validate_ip_or_cidr "example.com"
! validate_ip_or_cidr "1.2.3.4;rm"

validate_cidr_list "10.0.0.0/8" "fd00::/8"
! validate_cidr_list "10.0.0.1"

parse_rule_comment "allow nginx/v6 80/tcp frontend from:2001:db8::/64"
[[ "$PARSED_INSTANCE" == "nginx" ]]
[[ "$PARSED_PORT" == "80" ]]
[[ "$PARSED_PROTO" == "tcp" ]]
[[ "$PARSED_NETWORK" == "frontend" ]]
[[ "$PARSED_SOURCE" == "2001:db8::/64" ]]
[[ "$PARSED_IS_V6" == "1" ]]

key="$(normalized_rule_key "allow nginx/v6 80/tcp frontend from:2001:db8::/64")"
[[ "$key" == "nginx|80|tcp|frontend|2001:db8::/64" ]]

declare -F advanced_core_menu >/dev/null
declare -F core_raw_command_prompt >/dev/null
declare -F core_add_service_rule_prompt >/dev/null
declare -F enhanced_reload_rules >/dev/null
declare -F core_install_system_safe >/dev/null
declare -F show_grouped_rules >/dev/null
declare -F collect_rule_stats >/dev/null
declare -F rule_health_eval >/dev/null

rule_parse_line "[33] 172.19.0.2 8888/tcp ALLOW FWD Anywhere # allow hindsight 8888/tcp hindsight_default"
[[ "$RULEVIEW_NUMBER" == "33" ]]
[[ "$RULEVIEW_TARGET" == "172.19.0.2" ]]
[[ "$RULEVIEW_CONTAINER" == "hindsight" ]]
[[ "$RULEVIEW_PORT_PROTO" == "8888/tcp" ]]
[[ -z "$RULEVIEW_SOURCE" ]]

old_dry_run="$DRY_RUN"
DRY_RUN=1
install_plan="$(core_install_system_safe)"
DRY_RUN="$old_dry_run"
[[ "$install_plan" == *"ufw-docker"* ]]
[[ "$install_plan" == *"install"* ]]

[[ "$(NO_COLOR=1 "$menu" --version)" == "1.4.0" ]]
NO_COLOR=1 UFW_DOCKER_MENU_TESTING=1 "$menu" --self-test >/dev/null
NO_COLOR=1 COLUMNS=120 "$menu" --print-main-menu | grep -Fq "UFW-DOCKER"

printf "ufw-docker-menu tests passed\n"
