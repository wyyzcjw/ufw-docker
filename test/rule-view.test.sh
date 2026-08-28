#!/usr/bin/env bash
set -euo pipefail

working_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd -P)"
root_dir="${working_dir}/.."
menu="${root_dir}/ufw-docker-menu"

export NO_COLOR=1
export UFW_DOCKER_MENU_TESTING=1
export UFW_DOCKER_MENU_NO_PYTHON=1
# shellcheck disable=SC1090
source "$menu"

managed_rule_lines() {
    cat <<'EOF'
[30] 172.19.0.2 8888/tcp ALLOW FWD 104.224.155.35 # allow hindsight 8888/tcp hindsight_default from:104.224.155.35
[31] 172.19.0.2 9999/tcp ALLOW FWD Anywhere # allow hindsight 9999/tcp hindsight_default
[32] 172.20.0.2 7860/tcp ALLOW FWD 104.224.155.35 # allow aistudio-to-api 7860/tcp aistudio-to-api_default from:104.224.155.35
EOF
}

# Keep the test independent from a real Docker daemon while exercising the
# presentation and stats paths.
rule_health_eval() {
    local target="${3:-}"
    if [[ "$target" == "172.20.0.2" ]]; then
        RULEVIEW_HEALTH="stale"
    else
        RULEVIEW_HEALTH="ok"
    fi
}

[[ "$(rule_target_from_status_line "[30] 172.19.0.2 8888/tcp ALLOW FWD Anywhere # allow hindsight 8888/tcp hindsight_default")" == "172.19.0.2" ]]

rule_parse_line "[30] 172.19.0.2 8888/tcp ALLOW FWD 104.224.155.35 # allow hindsight 8888/tcp hindsight_default from:104.224.155.35"
[[ "$RULEVIEW_NUMBER" == "30" ]]
[[ "$RULEVIEW_CONTAINER" == "hindsight" ]]
[[ "$RULEVIEW_PORT_PROTO" == "8888/tcp" ]]
[[ "$RULEVIEW_NETWORK" == "hindsight_default" ]]
[[ "$RULEVIEW_SOURCE" == "104.224.155.35" ]]
[[ "$RULEVIEW_TARGET" == "172.19.0.2" ]]

COLUMNS=70
[[ "$(rule_view_mode)" == "card" ]]
COLUMNS=90
[[ "$(rule_view_mode)" == "compact" ]]
COLUMNS=120
[[ "$(rule_view_mode)" == "full" ]]

collect_rule_stats
[[ "$RULE_STATS_TOTAL" == "3" ]]
[[ "$RULE_STATS_CONTAINERS" == "2" ]]
[[ "$RULE_STATS_PUBLIC" == "1" ]]
[[ "$RULE_STATS_RESTRICTED" == "2" ]]
[[ "$RULE_STATS_V4" == "3" ]]
[[ "$RULE_STATS_V6" == "0" ]]
[[ "$RULE_STATS_HEALTHY" == "2" ]]
[[ "$RULE_STATS_UNHEALTHY" == "1" ]]
[[ "$RULE_STATS_UNVERIFIED" == "0" ]]

card_output="$(COLUMNS=70 show_managed_rules "" all card)"
grep -Fq '[#30] hindsight' <<< "$card_output"
grep -Fq '8888/tcp  <- 104.224.155.35' <<< "$card_output"
grep -Fq '9999/tcp  <- ANY' <<< "$card_output"
grep -Fq 'IP已变化' <<< "$card_output"

group_output="$(COLUMNS=70 show_grouped_rules)"
grep -Fq 'hindsight (2 条)' <<< "$group_output"
grep -Fq 'aistudio-to-api (1 条)' <<< "$group_output"

public_output="$(COLUMNS=90 show_managed_rules "" public compact)"
grep -Fq '#31' <<< "$public_output"
! grep -Fq '#30' <<< "$public_output"
! grep -Fq '#32' <<< "$public_output"

restricted_output="$(COLUMNS=90 show_managed_rules "" restricted compact)"
grep -Fq '#30' <<< "$restricted_output"
grep -Fq '#32' <<< "$restricted_output"
! grep -Fq '#31' <<< "$restricted_output"

unhealthy_output="$(COLUMNS=90 show_managed_rules "" unhealthy compact)"
grep -Fq '#32' <<< "$unhealthy_output"
grep -Fq 'IP已变化' <<< "$unhealthy_output"
! grep -Fq '#30' <<< "$unhealthy_output"

full_output="$(COLUMNS=120 show_managed_rules "" all full)"
grep -Fq 'Network' <<< "$full_output"
grep -Fq 'Target' <<< "$full_output"
grep -Fq 'hindsight_default' <<< "$full_output"

printf 'responsive rule view tests passed\n'
