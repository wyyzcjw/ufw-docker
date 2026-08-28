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

# Mock just the Docker calls used by rule_health_eval. A shell function is
# intentionally used so `command -v docker` also succeeds.
docker() {
    local area="${1:-}"
    local action="${2:-}"
    local instance=""

    if [[ "$area" == "info" ]]; then
        return 0
    fi

    if [[ "$area" == "container" && "$action" == "inspect" ]]; then
        if [[ "${3:-}" == "--format" ]]; then
            instance="${5:-}"
            case "$instance" in
                stopped) printf 'false\n'; return 0 ;;
                running) printf 'true\n'; return 0 ;;
                *) printf 'true\n'; return 0 ;;
            esac
        fi
        instance="${3:-}"
        case "$instance" in
            missing|swarm-service) return 1 ;;
            *) return 0 ;;
        esac
    fi

    if [[ "$area" == "service" && "$action" == "inspect" ]]; then
        instance="${3:-}"
        [[ "$instance" == "swarm-service" ]]
        return
    fi

    return 1
}

container_networks() {
    local instance="${1:-}"
    case "$instance" in
        running)
            printf 'frontend|172.19.0.2|2001:db8::2\n'
            ;;
        stopped)
            printf 'frontend|172.19.0.3|\n'
            ;;
        *)
            return 0
            ;;
    esac
}

RULE_HEALTH_CHECK=1
rule_health_cache_reset
rule_health_eval running frontend 172.19.0.2 0
[[ "$RULEVIEW_HEALTH" == "ok" ]]

rule_health_cache_reset
rule_health_eval running frontend 172.19.0.99 0
[[ "$RULEVIEW_HEALTH" == "stale" ]]

rule_health_cache_reset
rule_health_eval running frontend 2001:db8::2 1
[[ "$RULEVIEW_HEALTH" == "ok" ]]

rule_health_cache_reset
rule_health_eval missing frontend 172.19.0.2 0
[[ "$RULEVIEW_HEALTH" == "missing" ]]

rule_health_cache_reset
rule_health_eval stopped frontend 172.19.0.3 0
[[ "$RULEVIEW_HEALTH" == "stopped" ]]

rule_health_cache_reset
rule_health_eval swarm-service "" 10.0.0.2 0
[[ "$RULEVIEW_HEALTH" == "swarm" ]]

RULE_HEALTH_CHECK=0
rule_health_cache_reset
rule_health_eval running frontend 172.19.0.2 0
[[ "$RULEVIEW_HEALTH" == "disabled" ]]

printf 'rule health tests passed\n'
