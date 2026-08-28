#!/usr/bin/env bash
# shellcheck shell=bash
# Responsive, source-aware rule presentation and rule health checks.

RULE_HEALTH_CHECK="${UFW_DOCKER_MENU_RULE_HEALTH_CHECK:-1}"
RULEVIEW_DOCKER_AVAILABLE="unknown"
declare -gA RULEVIEW_HEALTH_CACHE=()

RULEVIEW_NUMBER=""
RULEVIEW_CONTAINER=""
RULEVIEW_PORT=""
RULEVIEW_PROTO=""
RULEVIEW_PORT_PROTO=""
RULEVIEW_NETWORK=""
RULEVIEW_SOURCE=""
RULEVIEW_IPV6="0"
RULEVIEW_TARGET=""
RULEVIEW_RAW=""
RULEVIEW_HEALTH="unknown"
RULEVIEW_HEALTH_LABEL="未知"
RULEVIEW_HEALTH_COLOR=""

RULE_STATS_TOTAL=0
RULE_STATS_CONTAINERS=0
RULE_STATS_PUBLIC=0
RULE_STATS_RESTRICTED=0
RULE_STATS_V4=0
RULE_STATS_V6=0
RULE_STATS_HEALTHY=0
RULE_STATS_UNHEALTHY=0
RULE_STATS_UNVERIFIED=0

rule_view_mode() {
    local requested="${UFW_DOCKER_MENU_RULE_VIEW:-auto}"
    local cols
    case "$requested" in
        card|compact|full)
            printf '%s\n' "$requested"
            return 0
            ;;
        auto|"") ;;
        *)
            requested="auto"
            ;;
    esac

    cols="$(terminal_cols)"
    if (( cols < 80 )); then
        printf 'card\n'
    elif (( cols < 110 )); then
        printf 'compact\n'
    else
        printf 'full\n'
    fi
}

rule_target_from_status_line() {
    local line="${1:-}"
    local re='^\[[[:blank:]]*[0-9]+\][[:blank:]]+([^[:blank:]]+)'
    if [[ "$line" =~ $re ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

rule_parse_line() {
    local line="${1:-}"
    local comment="" target=""

    RULEVIEW_NUMBER=""
    RULEVIEW_CONTAINER=""
    RULEVIEW_PORT=""
    RULEVIEW_PROTO=""
    RULEVIEW_PORT_PROTO=""
    RULEVIEW_NETWORK=""
    RULEVIEW_SOURCE=""
    RULEVIEW_IPV6="0"
    RULEVIEW_TARGET=""
    RULEVIEW_RAW="$line"

    if lifecycle_available && ufw_docker_parse_status_line "$line"; then
        RULEVIEW_NUMBER="$UFW_DOCKER_RULE_NUMBER"
        RULEVIEW_CONTAINER="$UFW_DOCKER_RULE_INSTANCE"
        RULEVIEW_PORT="$UFW_DOCKER_RULE_PORT"
        RULEVIEW_PROTO="$UFW_DOCKER_RULE_PROTO"
        RULEVIEW_NETWORK="$UFW_DOCKER_RULE_NETWORK"
        RULEVIEW_SOURCE="$UFW_DOCKER_RULE_SOURCE"
        RULEVIEW_IPV6="$UFW_DOCKER_RULE_IS_V6"
    else
        [[ "$line" == *'# allow '* ]] || return 1
        RULEVIEW_NUMBER="$(extract_rule_number "$line")"
        comment="${line##*# allow }"
        parse_rule_comment "allow $comment" || return 1
        RULEVIEW_CONTAINER="$PARSED_INSTANCE"
        RULEVIEW_PORT="$PARSED_PORT"
        RULEVIEW_PROTO="$PARSED_PROTO"
        RULEVIEW_NETWORK="$PARSED_NETWORK"
        RULEVIEW_SOURCE="$PARSED_SOURCE"
        RULEVIEW_IPV6="$PARSED_IS_V6"
    fi

    if [[ -n "$RULEVIEW_PORT" ]]; then
        RULEVIEW_PORT_PROTO="${RULEVIEW_PORT}/${RULEVIEW_PROTO}"
    fi
    target="$(rule_target_from_status_line "$line" 2>/dev/null || true)"
    RULEVIEW_TARGET="$target"
    [[ -n "$RULEVIEW_CONTAINER" ]]
}

rule_health_cache_reset() {
    RULEVIEW_HEALTH_CACHE=()
    RULEVIEW_DOCKER_AVAILABLE="unknown"
}

rule_docker_available() {
    if [[ "$RULEVIEW_DOCKER_AVAILABLE" == "1" ]]; then
        return 0
    fi
    if [[ "$RULEVIEW_DOCKER_AVAILABLE" == "0" ]]; then
        return 1
    fi
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        RULEVIEW_DOCKER_AVAILABLE="1"
        return 0
    fi
    RULEVIEW_DOCKER_AVAILABLE="0"
    return 1
}

rule_health_eval() {
    local instance="${1:-}"
    local network="${2:-}"
    local target="${3:-}"
    local is_v6="${4:-0}"
    local key running name ipv4 ipv6 address
    local matched_scope=0

    RULEVIEW_HEALTH="unknown"

    if [[ "$RULE_HEALTH_CHECK" == "0" ]]; then
        RULEVIEW_HEALTH="disabled"
        return 0
    fi
    if ! rule_docker_available; then
        RULEVIEW_HEALTH="unknown"
        return 0
    fi

    key="${instance}|${network}|${target}|${is_v6}"
    if [[ -n "${RULEVIEW_HEALTH_CACHE[$key]+x}" ]]; then
        RULEVIEW_HEALTH="${RULEVIEW_HEALTH_CACHE[$key]}"
        return 0
    fi

    if ! docker container inspect "$instance" >/dev/null 2>&1; then
        if docker service inspect "$instance" >/dev/null 2>&1; then
            RULEVIEW_HEALTH="swarm"
        else
            RULEVIEW_HEALTH="missing"
        fi
        RULEVIEW_HEALTH_CACHE["$key"]="$RULEVIEW_HEALTH"
        return 0
    fi

    running="$(docker container inspect --format '{{.State.Running}}' "$instance" 2>/dev/null || true)"
    if [[ "$running" != "true" ]]; then
        RULEVIEW_HEALTH="stopped"
        RULEVIEW_HEALTH_CACHE["$key"]="$RULEVIEW_HEALTH"
        return 0
    fi

    if [[ -z "$target" || "$target" == "Anywhere" || "$target" == "Anywhere(v6)" ]]; then
        RULEVIEW_HEALTH="unknown"
        RULEVIEW_HEALTH_CACHE["$key"]="$RULEVIEW_HEALTH"
        return 0
    fi

    while IFS='|' read -r name ipv4 ipv6; do
        [[ -n "$name" ]] || continue
        [[ -z "$network" || "$name" == "$network" ]] || continue
        matched_scope=1
        if [[ "$is_v6" == "1" ]]; then
            address="$ipv6"
        else
            address="$ipv4"
        fi
        if [[ -n "$address" && "$target" == "$address" ]]; then
            RULEVIEW_HEALTH="ok"
            RULEVIEW_HEALTH_CACHE["$key"]="$RULEVIEW_HEALTH"
            return 0
        fi
    done < <(container_networks "$instance" 2>/dev/null || true)

    if (( matched_scope == 0 )); then
        RULEVIEW_HEALTH="stale"
    else
        RULEVIEW_HEALTH="stale"
    fi
    RULEVIEW_HEALTH_CACHE["$key"]="$RULEVIEW_HEALTH"
}

rule_health_meta() {
    case "${1:-unknown}" in
        ok)
            RULEVIEW_HEALTH_LABEL="正常"
            RULEVIEW_HEALTH_COLOR="$C_GREEN"
            ;;
        stale)
            RULEVIEW_HEALTH_LABEL="IP已变化"
            RULEVIEW_HEALTH_COLOR="$C_RED"
            ;;
        missing)
            RULEVIEW_HEALTH_LABEL="容器不存在"
            RULEVIEW_HEALTH_COLOR="$C_RED"
            ;;
        stopped)
            RULEVIEW_HEALTH_LABEL="容器已停止"
            RULEVIEW_HEALTH_COLOR="$C_ORANGE"
            ;;
        swarm)
            RULEVIEW_HEALTH_LABEL="Swarm"
            RULEVIEW_HEALTH_COLOR="$C_CYAN"
            ;;
        disabled)
            RULEVIEW_HEALTH_LABEL="未检测"
            RULEVIEW_HEALTH_COLOR="$C_GRAY"
            ;;
        *)
            RULEVIEW_HEALTH_LABEL="未验证"
            RULEVIEW_HEALTH_COLOR="$C_GRAY"
            ;;
    esac
}

rule_health_is_unhealthy() {
    case "${1:-unknown}" in
        stale|missing|stopped) return 0 ;;
        *) return 1 ;;
    esac
}

rule_source_label() {
    if [[ -n "${1:-}" ]]; then
        printf '%s\n' "$1"
    else
        printf 'ANY\n'
    fi
}

rule_port_label() {
    local port_proto="${1:-}"
    local is_v6="${2:-0}"
    [[ -n "$port_proto" ]] || port_proto="all"
    [[ "$is_v6" == "1" ]] && port_proto+=" v6"
    printf '%s\n' "$port_proto"
}

rule_network_label() {
    [[ -n "${1:-}" ]] && printf '%s\n' "$1" || printf '%s\n' '-'
}

rule_target_label() {
    [[ -n "${1:-}" ]] && printf '%s\n' "$1" || printf '%s\n' '-'
}

truncate_text() {
    local text="${1:-}"
    local max="${2:-20}"
    if (( max < 4 )); then
        printf '%s' "${text:0:max}"
    elif (( ${#text} > max )); then
        printf '%s...' "${text:0:max-3}"
    else
        printf '%s' "$text"
    fi
}

rule_render_table_header() {
    case "${1:-compact}" in
        compact)
            printf '%-5s %-20s %-11s %-20s %-10s\n' \
                'No.' 'Container' 'Port' 'Source' 'Health'
            separator 76
            ;;
        full)
            printf '%-5s %-18s %-11s %-18s %-20s %-17s %-10s\n' \
                'No.' 'Container' 'Port' 'Source' 'Network' 'Target' 'Health'
            separator 110
            ;;
    esac
}

rule_render_current() {
    local mode="${1:-$(rule_view_mode)}"
    local number container port source network target source_color
    local cols max_container max_value

    rule_health_meta "$RULEVIEW_HEALTH"
    number="${RULEVIEW_NUMBER:-?}"
    source="$(rule_source_label "$RULEVIEW_SOURCE")"
    port="$(rule_port_label "$RULEVIEW_PORT_PROTO" "$RULEVIEW_IPV6")"
    network="$(rule_network_label "$RULEVIEW_NETWORK")"
    target="$(rule_target_label "$RULEVIEW_TARGET")"
    source_color="$C_GREEN"
    [[ "$source" == "ANY" ]] && source_color="$C_YELLOW"

    case "$mode" in
        card)
            cols="$(terminal_cols)"
            max_container=$(( cols - 22 ))
            (( max_container < 16 )) && max_container=16
            (( max_container > 42 )) && max_container=42
            max_value=$(( cols - 10 ))
            (( max_value < 20 )) && max_value=20
            (( max_value > 58 )) && max_value=58
            container="$(truncate_text "$RULEVIEW_CONTAINER" "$max_container")"
            source="$(truncate_text "$source" "$max_value")"
            network="$(truncate_text "$network" "$max_value")"
            target="$(truncate_text "$target" "$max_value")"
            printf '%s[#%s]%s %s%s%s  %s[%s]%s\n' \
                "$C_GRAY" "$number" "$C_RESET" \
                "$C_CYAN" "$container" "$C_RESET" \
                "$RULEVIEW_HEALTH_COLOR" "$RULEVIEW_HEALTH_LABEL" "$C_RESET"
            printf '  %s%s%s  <- %s%s%s\n' \
                "$C_MAGENTA" "$port" "$C_RESET" \
                "$source_color" "$source" "$C_RESET"
            printf '  net %s%s%s\n' "$C_CYAN" "$network" "$C_RESET"
            printf '  dst %s%s%s\n' "$C_BLUE" "$target" "$C_RESET"
            ;;
        full)
            container="$(truncate_text "$RULEVIEW_CONTAINER" 18)"
            source="$(truncate_text "$source" 18)"
            network="$(truncate_text "$network" 20)"
            target="$(truncate_text "$target" 17)"
            printf '%-5s ' "#$number"
            printf '%s%-18s%s ' "$C_CYAN" "$container" "$C_RESET"
            printf '%s%-11s%s ' "$C_MAGENTA" "$port" "$C_RESET"
            printf '%s%-18s%s ' "$source_color" "$source" "$C_RESET"
            printf '%s%-20s%s ' "$C_CYAN" "$network" "$C_RESET"
            printf '%s%-17s%s ' "$C_BLUE" "$target" "$C_RESET"
            printf '%s%-10s%s\n' "$RULEVIEW_HEALTH_COLOR" "$RULEVIEW_HEALTH_LABEL" "$C_RESET"
            ;;
        *)
            container="$(truncate_text "$RULEVIEW_CONTAINER" 20)"
            source="$(truncate_text "$source" 20)"
            printf '%-5s ' "#$number"
            printf '%s%-20s%s ' "$C_CYAN" "$container" "$C_RESET"
            printf '%s%-11s%s ' "$C_MAGENTA" "$port" "$C_RESET"
            printf '%s%-20s%s ' "$source_color" "$source" "$C_RESET"
            printf '%s%-10s%s\n' "$RULEVIEW_HEALTH_COLOR" "$RULEVIEW_HEALTH_LABEL" "$C_RESET"
            ;;
    esac
}

rule_kind_matches() {
    local kind="${1:-all}"
    case "$kind" in
        all) return 0 ;;
        public) [[ -z "$RULEVIEW_SOURCE" ]] ;;
        restricted) [[ -n "$RULEVIEW_SOURCE" ]] ;;
        unhealthy) rule_health_is_unhealthy "$RULEVIEW_HEALTH" ;;
        *) return 1 ;;
    esac
}

rule_filter_matches() {
    local filter="${1:-}"
    [[ -z "$filter" ]] && return 0
    [[ "${RULEVIEW_CONTAINER,,}" == *"${filter,,}"* ]]
}

show_managed_rules() {
    local filter="${1:-}"
    local kind="${2:-all}"
    local mode="${3:-$(rule_view_mode)}"
    local line found=0 header=0

    rule_health_cache_reset
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        rule_parse_line "$line" || continue
        rule_filter_matches "$filter" || continue
        rule_health_eval "$RULEVIEW_CONTAINER" "$RULEVIEW_NETWORK" "$RULEVIEW_TARGET" "$RULEVIEW_IPV6"
        rule_kind_matches "$kind" || continue

        if [[ "$mode" != "card" && "$header" == "0" ]]; then
            rule_render_table_header "$mode"
            header=1
        fi
        [[ "$found" == "0" || "$mode" != "card" ]] || printf '\n'
        rule_render_current "$mode"
        found=1
    done < <(managed_rule_lines)

    (( found == 1 )) || say "没有匹配的 UFW-Docker 规则。"
}

rule_render_group_current() {
    local cols source port network target source_color number
    rule_health_meta "$RULEVIEW_HEALTH"
    cols="$(terminal_cols)"
    number="${RULEVIEW_NUMBER:-?}"
    source="$(rule_source_label "$RULEVIEW_SOURCE")"
    port="$(rule_port_label "$RULEVIEW_PORT_PROTO" "$RULEVIEW_IPV6")"
    network="$(rule_network_label "$RULEVIEW_NETWORK")"
    target="$(rule_target_label "$RULEVIEW_TARGET")"
    source_color="$C_GREEN"
    [[ "$source" == "ANY" ]] && source_color="$C_YELLOW"

    source="$(truncate_text "$source" 24)"
    network="$(truncate_text "$network" 28)"
    target="$(truncate_text "$target" 24)"

    printf '  %s#%-3s%s %s%-12s%s <- %s%s%s  %s[%s]%s\n' \
        "$C_GRAY" "$number" "$C_RESET" \
        "$C_MAGENTA" "$port" "$C_RESET" \
        "$source_color" "$source" "$C_RESET" \
        "$RULEVIEW_HEALTH_COLOR" "$RULEVIEW_HEALTH_LABEL" "$C_RESET"
    if (( cols < 100 )); then
        printf '       %s%s%s -> %s%s%s\n' \
            "$C_CYAN" "$network" "$C_RESET" \
            "$C_BLUE" "$target" "$C_RESET"
    else
        printf '       network=%s%s%s  target=%s%s%s\n' \
            "$C_CYAN" "$network" "$C_RESET" \
            "$C_BLUE" "$target" "$C_RESET"
    fi
}

show_grouped_rules() {
    local filter="${1:-}"
    local kind="${2:-all}"
    local line container
    local found=0
    local -A group_data=() group_count=()
    local -a order=()

    rule_health_cache_reset
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        rule_parse_line "$line" || continue
        rule_filter_matches "$filter" || continue
        rule_health_eval "$RULEVIEW_CONTAINER" "$RULEVIEW_NETWORK" "$RULEVIEW_TARGET" "$RULEVIEW_IPV6"
        rule_kind_matches "$kind" || continue
        container="$RULEVIEW_CONTAINER"
        if [[ -z "${group_count[$container]+x}" ]]; then
            order+=("$container")
            group_count["$container"]=0
        fi
        group_count["$container"]=$(( ${group_count[$container]} + 1 ))
        group_data["$container"]="${group_data[$container]-}${line}"$'\n'
        found=1
    done < <(managed_rule_lines)

    if (( found == 0 )); then
        say "没有匹配的 UFW-Docker 规则。"
        return 0
    fi

    for container in "${order[@]}"; do
        printf '%s%s%s %s(%s 条)%s\n' \
            "$C_BOLD$C_CYAN" "$container" "$C_RESET" \
            "$C_GRAY" "${group_count[$container]}" "$C_RESET"
        separator
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            rule_parse_line "$line" || continue
            rule_health_eval "$RULEVIEW_CONTAINER" "$RULEVIEW_NETWORK" "$RULEVIEW_TARGET" "$RULEVIEW_IPV6"
            rule_render_group_current
        done <<< "${group_data[$container]}"
        printf '\n'
    done
}

collect_rule_stats() {
    local line
    local -A containers=()

    RULE_STATS_TOTAL=0
    RULE_STATS_CONTAINERS=0
    RULE_STATS_PUBLIC=0
    RULE_STATS_RESTRICTED=0
    RULE_STATS_V4=0
    RULE_STATS_V6=0
    RULE_STATS_HEALTHY=0
    RULE_STATS_UNHEALTHY=0
    RULE_STATS_UNVERIFIED=0
    rule_health_cache_reset

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        rule_parse_line "$line" || continue
        RULE_STATS_TOTAL=$(( RULE_STATS_TOTAL + 1 ))
        containers["$RULEVIEW_CONTAINER"]=1
        if [[ -n "$RULEVIEW_SOURCE" ]]; then
            RULE_STATS_RESTRICTED=$(( RULE_STATS_RESTRICTED + 1 ))
        else
            RULE_STATS_PUBLIC=$(( RULE_STATS_PUBLIC + 1 ))
        fi
        if [[ "$RULEVIEW_IPV6" == "1" ]]; then
            RULE_STATS_V6=$(( RULE_STATS_V6 + 1 ))
        else
            RULE_STATS_V4=$(( RULE_STATS_V4 + 1 ))
        fi

        rule_health_eval "$RULEVIEW_CONTAINER" "$RULEVIEW_NETWORK" "$RULEVIEW_TARGET" "$RULEVIEW_IPV6"
        case "$RULEVIEW_HEALTH" in
            ok) RULE_STATS_HEALTHY=$(( RULE_STATS_HEALTHY + 1 )) ;;
            stale|missing|stopped) RULE_STATS_UNHEALTHY=$(( RULE_STATS_UNHEALTHY + 1 )) ;;
            *) RULE_STATS_UNVERIFIED=$(( RULE_STATS_UNVERIFIED + 1 )) ;;
        esac
    done < <(managed_rule_lines)

    RULE_STATS_CONTAINERS="${#containers[@]}"
}

show_rule_summary() {
    printf '%s规则概览%s\n' "$C_BOLD" "$C_RESET"
    printf '  规则记录: %s%-4s%s  涉及容器: %s%s%s\n' \
        "$C_CYAN" "$RULE_STATS_TOTAL" "$C_RESET" \
        "$C_CYAN" "$RULE_STATS_CONTAINERS" "$C_RESET"
    printf '  公开 ANY: %s%-4s%s  指定来源: %s%s%s\n' \
        "$C_YELLOW" "$RULE_STATS_PUBLIC" "$C_RESET" \
        "$C_GREEN" "$RULE_STATS_RESTRICTED" "$C_RESET"
    printf '  IPv4: %s%-4s%s       IPv6: %s%s%s\n' \
        "$C_BLUE" "$RULE_STATS_V4" "$C_RESET" \
        "$C_BLUE" "$RULE_STATS_V6" "$C_RESET"
    printf '  正常: %s%-4s%s       异常: %s%-4s%s  未验证: %s%s%s\n' \
        "$C_GREEN" "$RULE_STATS_HEALTHY" "$C_RESET" \
        "$C_RED" "$RULE_STATS_UNHEALTHY" "$C_RESET" \
        "$C_GRAY" "$RULE_STATS_UNVERIFIED" "$C_RESET"
}

rule_render_recent_current() {
    local cols number container port source source_color
    cols="$(terminal_cols)"
    number="${RULEVIEW_NUMBER:-?}"
    container="$(truncate_text "$RULEVIEW_CONTAINER" 18)"
    port="$(rule_port_label "$RULEVIEW_PORT_PROTO" "$RULEVIEW_IPV6")"
    source="$(truncate_text "$(rule_source_label "$RULEVIEW_SOURCE")" 20)"
    source_color="$C_GREEN"
    [[ "$source" == "ANY" ]] && source_color="$C_YELLOW"
    rule_health_meta "$RULEVIEW_HEALTH"

    if (( cols < 60 )); then
        printf '  %s#%s%s %s%s%s %s[%s]%s\n' \
            "$C_GRAY" "$number" "$C_RESET" \
            "$C_CYAN" "$container" "$C_RESET" \
            "$RULEVIEW_HEALTH_COLOR" "$RULEVIEW_HEALTH_LABEL" "$C_RESET"
        printf '      %s%s%s <- %s%s%s\n' \
            "$C_MAGENTA" "$port" "$C_RESET" \
            "$source_color" "$source" "$C_RESET"
    else
        printf '  %s#%-3s%s %s%-18s%s %s%-11s%s <- %s%-20s%s %s[%s]%s\n' \
            "$C_GRAY" "$number" "$C_RESET" \
            "$C_CYAN" "$container" "$C_RESET" \
            "$C_MAGENTA" "$port" "$C_RESET" \
            "$source_color" "$source" "$C_RESET" \
            "$RULEVIEW_HEALTH_COLOR" "$RULEVIEW_HEALTH_LABEL" "$C_RESET"
    fi
}

show_recent_rules() {
    local limit="${1:-4}"
    local line i
    local -a recent=()

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        recent+=("$line")
        if (( ${#recent[@]} > limit )); then
            recent=("${recent[@]:1}")
        fi
    done < <(managed_rule_lines)

    if (( ${#recent[@]} == 0 )); then
        say "  当前没有 UFW-Docker 规则。"
        return 0
    fi

    i=$(( ${#recent[@]} - 1 ))
    while (( i >= 0 )); do
        if rule_parse_line "${recent[$i]}"; then
            rule_health_eval "$RULEVIEW_CONTAINER" "$RULEVIEW_NETWORK" "$RULEVIEW_TARGET" "$RULEVIEW_IPV6"
            rule_render_recent_current
        fi
        i=$(( i - 1 ))
    done
}

show_dashboard() {
    clear_screen
    render_banner
    separator
    printf '%s环境状态%s\n\n' "$C_BOLD" "$C_RESET"
    printf '  %-18s %s\n' "内核" "$(uname -srmo 2>/dev/null || uname -a)"
    printf '  %-18s %s\n' "Bash" "$BASH_VERSION"
    printf '  %-18s %s\n' "UFW" "$(ufw_state)"
    printf '  %-18s %s\n' "Docker" "$(docker_state)"
    printf '  %-18s %s\n' "iptables" "$(iptables_backend)"
    printf '  %-18s %s\n' "IPv6 工具" "$(command -v ip6tables >/dev/null 2>&1 && printf '可用' || printf '不可用')"
    printf '  %-18s %s\n' "自动重载服务" "$(service_state)"
    if resolve_core >/dev/null; then
        printf '  %-18s %s\n' "核心命令" "$CORE_BIN"
    else
        printf '  %-18s %s\n' "核心命令" "未找到"
    fi
    printf '  %-18s %s\n' "菜单脚本" "$SCRIPT_PATH"

    printf '\n'
    separator
    collect_rule_stats
    show_rule_summary

    printf '\n%s最近规则%s\n' "$C_BOLD" "$C_RESET"
    separator
    show_recent_rules 4
    printf '\n%s提示：%s输入主菜单 4 查看完整规则管理。\n' "$C_GRAY" "$C_RESET"
    pause_screen
}

select_rule_container() {
    local line container choice idx
    local -A counts=()
    local -a order=()

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        rule_parse_line "$line" || continue
        container="$RULEVIEW_CONTAINER"
        if [[ -z "${counts[$container]+x}" ]]; then
            order+=("$container")
            counts["$container"]=0
        fi
        counts["$container"]=$(( ${counts[$container]} + 1 ))
    done < <(managed_rule_lines)

    (( ${#order[@]} > 0 )) || {
        warn "当前没有 UFW-Docker 规则。"
        return 1
    }

    printf '%s请选择规则所属容器：%s\n' "$C_BOLD" "$C_RESET"
    idx=1
    for container in "${order[@]}"; do
        printf '  %s%2d.%s %-32s %s%s 条%s\n' \
            "$C_GREEN" "$idx" "$C_RESET" \
            "$(truncate_text "$container" 32)" \
            "$C_GRAY" "${counts[$container]}" "$C_RESET"
        idx=$(( idx + 1 ))
    done
    say "  0. 返回"
    printf '选择：'
    read -r choice || return 1
    [[ "$choice" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#order[@]} )) || return 1
    SELECTED_CONTAINER="${order[choice-1]}"
}

delete_selected_managed_numbers() {
    local input numbers_text token line number
    local -a numbers=()
    local -A allowed=()

    show_managed_rules
    printf '\n输入要删除的规则编号，可用空格或逗号分隔：'
    read -r input || return 1
    input="${input//,/ }"
    read -r -a numbers <<< "$input"
    (( ${#numbers[@]} > 0 )) || return 1

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        number="$(extract_rule_number "$line")"
        [[ -n "$number" ]] && allowed["$number"]=1
    done < <(managed_rule_lines)

    for token in "${numbers[@]}"; do
        [[ "$token" =~ ^[0-9]+$ ]] || {
            error "规则编号无效：$token"
            return 1
        }
        [[ -n "${allowed[$token]+x}" ]] || {
            error "规则 #$token 不是当前 UFW-Docker 已管理规则，已拒绝删除。"
            return 1
        }
    done

    numbers_text="${numbers[*]}"
    delete_rules_by_numbers "$numbers_text"
}

delete_container_rules() {
    local line number
    local -a matched=()

    select_rule_container || return 1
    clear_screen
    printf '%s%s%s 的已管理规则\n' "$C_BOLD$C_CYAN" "$SELECTED_CONTAINER" "$C_RESET"
    separator
    rule_health_cache_reset
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        rule_parse_line "$line" || continue
        [[ "$RULEVIEW_CONTAINER" == "$SELECTED_CONTAINER" ]] || continue
        rule_health_eval "$RULEVIEW_CONTAINER" "$RULEVIEW_NETWORK" "$RULEVIEW_TARGET" "$RULEVIEW_IPV6"
        rule_render_current "$(rule_view_mode)"
        number="$RULEVIEW_NUMBER"
        [[ -n "$number" ]] && matched+=("$number")
    done < <(managed_rule_lines)

    if (( ${#matched[@]} == 0 )); then
        warn "没有找到该容器的规则。"
        return 0
    fi
    printf '\n'
    delete_rules_by_numbers "${matched[*]}"
}

rule_delete_menu() {
    local choice
    while true; do
        clear_screen
        render_banner
        separator
        say "  1. 按 UFW-Docker 规则编号删除"
        say "  2. 删除某容器的全部已管理规则"
        say "  0. 返回"
        separator
        printf '选择：'
        read -r choice || choice=0
        case "$choice" in
            1) clear_screen; delete_selected_managed_numbers; pause_screen ;;
            2) clear_screen; delete_container_rules; pause_screen ;;
            0) return ;;
            *) warn "无效选择。"; pause_screen ;;
        esac
    done
}

rule_core_advanced_menu() {
    local choice
    while true; do
        clear_screen
        render_banner
        separator
        say "  1. 核心 list 按容器/端口/网络查询"
        say "  2. 核心 delete allow 删除普通规则"
        say "  3. rulectl TSV 原始结构化清单"
        say "  0. 返回"
        separator
        printf '选择：'
        read -r choice || choice=0
        case "$choice" in
            1) clear_screen; core_filtered_list; pause_screen ;;
            2) clear_screen; core_filtered_delete; pause_screen ;;
            3) clear_screen; rulectl_view_prompt; pause_screen ;;
            0) return ;;
            *) warn "无效选择。"; pause_screen ;;
        esac
    done
}

show_raw_ufw_numbered() {
    require_command ufw || return 1
    ufw status numbered 2>&1 || true
}

rules_menu() {
    local choice filter
    while true; do
        clear_screen
        render_banner
        separator
        say "  1. 按容器分组查看规则（推荐）"
        say "  2. 全部规则（自动适配终端宽度）"
        say "  3. 仅查看公开规则 ANY"
        say "  4. 仅查看指定来源 IP/CIDR 规则"
        say "  5. 查看异常/失效规则"
        say "  6. 搜索容器规则"
        say "  7. 删除规则  ▶"
        say "  8. 修复 / Reload  ▶"
        say "  9. 查看原始 UFW numbered 状态"
        say " 10. 核心 / rulectl 高级入口  ▶"
        say "  0. 返回"
        separator
        printf '选择：'
        read -r choice || choice=0
        case "$choice" in
            1) clear_screen; show_grouped_rules; pause_screen ;;
            2) clear_screen; show_managed_rules; pause_screen ;;
            3) clear_screen; show_managed_rules "" public; pause_screen ;;
            4) clear_screen; show_managed_rules "" restricted; pause_screen ;;
            5) clear_screen; show_managed_rules "" unhealthy; pause_screen ;;
            6)
                printf '输入容器名称关键字：'
                read -r filter || filter=""
                clear_screen
                show_grouped_rules "$filter"
                pause_screen
                ;;
            7) rule_delete_menu ;;
            8) reload_menu ;;
            9) clear_screen; show_raw_ufw_numbered; pause_screen ;;
            10) rule_core_advanced_menu ;;
            0) return ;;
            *) warn "无效选择。"; pause_screen ;;
        esac
    done
}
