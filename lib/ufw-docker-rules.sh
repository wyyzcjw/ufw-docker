#!/usr/bin/env bash
# shellcheck shell=bash
# Shared parser and lifecycle helpers for ufw-docker managed UFW rules.

UFW_DOCKER_RULE_INSTANCE=""
UFW_DOCKER_RULE_PORT=""
UFW_DOCKER_RULE_PROTO=""
UFW_DOCKER_RULE_NETWORK=""
UFW_DOCKER_RULE_SOURCE=""
UFW_DOCKER_RULE_IS_V6="0"
UFW_DOCKER_RULE_NUMBER=""
UFW_DOCKER_RULE_RAW=""

ufw_docker_rule_reset() {
    UFW_DOCKER_RULE_INSTANCE=""
    UFW_DOCKER_RULE_PORT=""
    UFW_DOCKER_RULE_PROTO=""
    UFW_DOCKER_RULE_NETWORK=""
    UFW_DOCKER_RULE_SOURCE=""
    UFW_DOCKER_RULE_IS_V6="0"
    UFW_DOCKER_RULE_NUMBER=""
    UFW_DOCKER_RULE_RAW=""
}

ufw_docker_parse_comment() {
    local comment="${1:-}"
    local -a tokens=()
    local token

    ufw_docker_rule_reset
    comment="${comment#\# allow }"
    comment="${comment#allow }"
    read -r -a tokens <<< "$comment"
    (( ${#tokens[@]} > 0 )) || return 1

    UFW_DOCKER_RULE_INSTANCE="${tokens[0]}"
    if [[ "$UFW_DOCKER_RULE_INSTANCE" == */v6 ]]; then
        UFW_DOCKER_RULE_INSTANCE="${UFW_DOCKER_RULE_INSTANCE%/v6}"
        UFW_DOCKER_RULE_IS_V6="1"
    fi
    [[ "$UFW_DOCKER_RULE_INSTANCE" =~ ^[-_.[:alnum:]]+$ ]] || return 1
    [[ -n "$UFW_DOCKER_RULE_INSTANCE" ]] || return 1

    for token in "${tokens[@]:1}"; do
        if [[ "$token" =~ ^([0-9]+)/(tcp|udp)$ ]]; then
            UFW_DOCKER_RULE_PORT="${BASH_REMATCH[1]}"
            UFW_DOCKER_RULE_PROTO="${BASH_REMATCH[2]}"
            (( UFW_DOCKER_RULE_PORT >= 1 && UFW_DOCKER_RULE_PORT <= 65535 )) || return 1
        elif [[ "$token" == from:* ]]; then
            [[ -z "$UFW_DOCKER_RULE_SOURCE" ]] || return 1
            UFW_DOCKER_RULE_SOURCE="${token#from:}"
            [[ -n "$UFW_DOCKER_RULE_SOURCE" && "$UFW_DOCKER_RULE_SOURCE" != *[[:space:]]* ]] || return 1
        elif [[ -z "$UFW_DOCKER_RULE_NETWORK" ]]; then
            [[ "$token" =~ ^[-_.[:alnum:]]+$ ]] || return 1
            UFW_DOCKER_RULE_NETWORK="$token"
        else
            return 1
        fi
    done

    if [[ -n "$UFW_DOCKER_RULE_PORT" && -z "$UFW_DOCKER_RULE_PROTO" ]]; then
        return 1
    fi
    return 0
}

ufw_docker_parse_status_line() {
    local line="${1:-}"
    local comment number=""
    ufw_docker_rule_reset
    [[ "$line" == *"# allow "* ]] || return 1

    if [[ "$line" =~ ^\[[[:blank:]]*([0-9]+)\] ]]; then
        number="${BASH_REMATCH[1]}"
    fi
    comment="${line##*# allow }"
    ufw_docker_parse_comment "allow $comment" || return 1
    UFW_DOCKER_RULE_NUMBER="$number"
    UFW_DOCKER_RULE_RAW="$line"
    return 0
}

ufw_docker_rule_key() {
    printf '%s|%s|%s|%s|%s\n' \
        "$UFW_DOCKER_RULE_INSTANCE" \
        "$UFW_DOCKER_RULE_PORT" \
        "$UFW_DOCKER_RULE_PROTO" \
        "$UFW_DOCKER_RULE_NETWORK" \
        "$UFW_DOCKER_RULE_SOURCE"
}

ufw_docker_rule_comment() {
    local name="$UFW_DOCKER_RULE_INSTANCE"
    [[ "$UFW_DOCKER_RULE_IS_V6" == "1" ]] && name+="/v6"
    printf 'allow %s' "$name"
    [[ -n "$UFW_DOCKER_RULE_PORT" ]] && printf ' %s/%s' "$UFW_DOCKER_RULE_PORT" "$UFW_DOCKER_RULE_PROTO"
    [[ -n "$UFW_DOCKER_RULE_NETWORK" ]] && printf ' %s' "$UFW_DOCKER_RULE_NETWORK"
    [[ -n "$UFW_DOCKER_RULE_SOURCE" ]] && printf ' from:%s' "$UFW_DOCKER_RULE_SOURCE"
    printf '\n'
}

ufw_docker_rule_matches() {
    local instance="${1:-}"
    local port_proto="${2:-}"
    local network="${3:-}"
    local source="${4:-}"
    local port="" proto=""

    if [[ -n "$port_proto" ]]; then
        port="${port_proto%/*}"
        proto="${port_proto#*/}"
    fi

    [[ -z "$instance" || "$UFW_DOCKER_RULE_INSTANCE" == "$instance" ]] || return 1
    [[ -z "$port" || "$UFW_DOCKER_RULE_PORT" == "$port" ]] || return 1
    [[ -z "$proto" || "$UFW_DOCKER_RULE_PROTO" == "$proto" ]] || return 1
    [[ -z "$network" || "$UFW_DOCKER_RULE_NETWORK" == "$network" ]] || return 1
    [[ -z "$source" || "$UFW_DOCKER_RULE_SOURCE" == "$source" ]] || return 1
    return 0
}

ufw_docker_validate_port_proto() {
    local value="${1:-}"
    [[ -z "$value" ]] && return 0
    [[ "$value" =~ ^([1-9][0-9]{0,4})/(tcp|udp)$ ]] || return 1
    (( BASH_REMATCH[1] >= 1 && BASH_REMATCH[1] <= 65535 ))
}

ufw_docker_source_family() {
    [[ "${1:-}" == *:* ]] && printf '6\n' || printf '4\n'
}

ufw_docker_container_network_rows() {
    local instance="${1:?missing container}"
    docker inspect --format \
        '{{range $name,$net := .NetworkSettings.Networks}}{{$name}}{{"|"}}{{$net.IPAddress}}{{"|"}}{{$net.GlobalIPv6Address}}{{"\n"}}{{end}}' \
        "$instance" 2>/dev/null | sed '/^[[:space:]]*$/d'
}

ufw_docker_container_published_ports() {
    local instance="${1:?missing container}"
    docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{with $conf}}{{$p}}{{"\n"}}{{end}}{{end}}' \
        "$instance" 2>/dev/null | sed '/^[[:space:]]*$/d' | sort -u
}

# Apply a source-restricted rule without crossing IP families. The original
# fork core allow-ip walks both IPv4 and IPv6 container targets; pairing an
# IPv4 source with an IPv6 target (or vice versa) can make UFW fail after some
# rules were already written. This helper deliberately selects only targets in
# the same family as SOURCE and is shared by the menu and lifecycle reload.
ufw_docker_apply_source_rule() {
    local source="${1:?missing source}"
    local instance="${2:?missing container}"
    local requested_port="${3:-}"
    local requested_proto="${4:-}"
    local network="${5:-}"
    local dry_run="${6:-0}"
    local source_family row name ipv4 ipv6 target suffix port_proto port proto comment
    local count=0 failed=0
    local -a rows=() ports=() command=()

    command -v docker >/dev/null 2>&1 || {
        printf 'docker executable not found\n' >&2
        return 1
    }
    command -v ufw >/dev/null 2>&1 || {
        printf 'ufw executable not found\n' >&2
        return 1
    }
    docker inspect "$instance" >/dev/null 2>&1 || {
        printf 'Docker instance "%s" does not exist.\n' "$instance" >&2
        return 1
    }

    if [[ -n "$requested_port" || -n "$requested_proto" ]]; then
        [[ -n "$requested_port" && -n "$requested_proto" ]] || {
            printf 'port and protocol must be provided together\n' >&2
            return 2
        }
    fi

    mapfile -t rows < <(ufw_docker_container_network_rows "$instance")
    mapfile -t ports < <(ufw_docker_container_published_ports "$instance")
    (( ${#rows[@]} > 0 )) || {
        printf 'Could not find a running instance "%s".\n' "$instance" >&2
        return 1
    }
    (( ${#ports[@]} > 0 )) || {
        printf '"%s" does not have any published ports.\n' "$instance" >&2
        return 1
    }

    source_family="$(ufw_docker_source_family "$source")"
    for port_proto in "${ports[@]}"; do
        port="${port_proto%/*}"
        proto="${port_proto#*/}"
        if [[ -n "$requested_port" ]] &&
           [[ "$port" != "$requested_port" || "$proto" != "$requested_proto" ]]; then
            continue
        fi

        for row in "${rows[@]}"; do
            IFS='|' read -r name ipv4 ipv6 <<< "$row"
            [[ -z "$network" || "$name" == "$network" ]] || continue

            if [[ "$source_family" == "4" ]]; then
                target="$ipv4"
                suffix=""
            else
                target="$ipv6"
                suffix="/v6"
            fi
            [[ -n "$target" ]] || continue

            comment="allow ${instance}${suffix} ${port}/${proto} ${name} from:${source}"
            command=(ufw route allow proto "$proto" from "$source" to "$target" port "$port" comment "$comment")

            printf 'source-rule: '
            printf '%q ' "${command[@]}"
            printf '\n'
            if [[ "$dry_run" != "1" ]] && ! "${command[@]}"; then
                failed=1
            fi
            (( ++count ))
        done
    done

    if (( count == 0 )); then
        printf 'No matching IPv%s target/published-port combination for %s.\n' \
            "$source_family" "$instance" >&2
        return 1
    fi
    (( failed == 0 ))
}

ufw_docker_managed_status_lines() {
    LC_ALL=C ufw status numbered 2>/dev/null |
        grep -F 'ALLOW FWD' |
        grep -F '# allow ' || true
}

ufw_docker_emit_tsv_header() {
    printf 'number\tcontainer\tport\tproto\tnetwork\tsource\tipv6\n'
}

ufw_docker_emit_tsv_rule() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$UFW_DOCKER_RULE_NUMBER" \
        "$UFW_DOCKER_RULE_INSTANCE" \
        "$UFW_DOCKER_RULE_PORT" \
        "$UFW_DOCKER_RULE_PROTO" \
        "$UFW_DOCKER_RULE_NETWORK" \
        "$UFW_DOCKER_RULE_SOURCE" \
        "$UFW_DOCKER_RULE_IS_V6"
}

ufw_docker_list_rules() {
    local instance="${1:-}"
    local port_proto="${2:-}"
    local network="${3:-}"
    local source="${4:-}"
    local format="${5:-text}"
    local line found=1

    [[ "$format" == "text" || "$format" == "tsv" ]] || return 2
    [[ "$format" == "tsv" ]] && ufw_docker_emit_tsv_header

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        ufw_docker_parse_status_line "$line" || continue
        ufw_docker_rule_matches "$instance" "$port_proto" "$network" "$source" || continue
        found=0
        if [[ "$format" == "tsv" ]]; then
            ufw_docker_emit_tsv_rule
        else
            printf '%s\n' "$line"
        fi
    done < <(ufw_docker_managed_status_lines)
    return "$found"
}

ufw_docker_collect_rule_numbers() {
    local instance="${1:-}"
    local port_proto="${2:-}"
    local network="${3:-}"
    local source="${4:-}"
    local line

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        ufw_docker_parse_status_line "$line" || continue
        ufw_docker_rule_matches "$instance" "$port_proto" "$network" "$source" || continue
        [[ -n "$UFW_DOCKER_RULE_NUMBER" ]] && printf '%s\n' "$UFW_DOCKER_RULE_NUMBER"
    done < <(ufw_docker_managed_status_lines)
}

ufw_docker_delete_rules() {
    local instance="${1:-}"
    local port_proto="${2:-}"
    local network="${3:-}"
    local source="${4:-}"
    local dry_run="${5:-0}"
    local -a numbers=()
    local number

    mapfile -t numbers < <(ufw_docker_collect_rule_numbers "$instance" "$port_proto" "$network" "$source" | sort -rn -u)
    (( ${#numbers[@]} > 0 )) || return 1

    for number in "${numbers[@]}"; do
        printf 'delete "%s"\n' "$number"
        if [[ "$dry_run" == "1" ]]; then
            printf 'ufw delete %q\n' "$number"
        else
            printf 'y\n' | ufw delete "$number" || true
        fi
    done
}

ufw_docker_rule_to_command() {
    local core="${1:?missing ufw-docker core path}"
    local -a command=()
    if [[ -n "$UFW_DOCKER_RULE_SOURCE" ]]; then
        command=("$core" allow-ip "$UFW_DOCKER_RULE_SOURCE" "$UFW_DOCKER_RULE_INSTANCE")
    else
        command=("$core" allow "$UFW_DOCKER_RULE_INSTANCE")
    fi
    [[ -n "$UFW_DOCKER_RULE_PORT" ]] && command+=("${UFW_DOCKER_RULE_PORT}/${UFW_DOCKER_RULE_PROTO}")
    [[ -n "$UFW_DOCKER_RULE_NETWORK" ]] && command+=("$UFW_DOCKER_RULE_NETWORK")
    printf '%q ' "${command[@]}"
    printf '\n'
}

ufw_docker_reload_rules() {
    local core="${1:?missing ufw-docker core path}"
    local dry_run="${2:-0}"
    local -A seen=()
    local -a comments=() failures=()
    local line key
    local -a command=()

    mapfile -t comments < <(ufw_docker_managed_status_lines)
    (( ${#comments[@]} > 0 )) || return 0

    for line in "${comments[@]}"; do
        ufw_docker_parse_status_line "$line" || {
            failures+=("cannot parse: $line")
            continue
        }
        key="$(ufw_docker_rule_key)"
        [[ -z "${seen[$key]+x}" ]] || continue
        seen["$key"]=1

        if [[ -n "$UFW_DOCKER_RULE_SOURCE" ]]; then
            printf 'reload source rule: %s\n' "$key"
            if ! ufw_docker_apply_source_rule \
                "$UFW_DOCKER_RULE_SOURCE" \
                "$UFW_DOCKER_RULE_INSTANCE" \
                "$UFW_DOCKER_RULE_PORT" \
                "$UFW_DOCKER_RULE_PROTO" \
                "$UFW_DOCKER_RULE_NETWORK" \
                "$dry_run"; then
                failures+=("failed: $key")
            fi
            continue
        fi

        command=("$core" allow "$UFW_DOCKER_RULE_INSTANCE")
        [[ -n "$UFW_DOCKER_RULE_PORT" ]] && command+=("${UFW_DOCKER_RULE_PORT}/${UFW_DOCKER_RULE_PROTO}")
        [[ -n "$UFW_DOCKER_RULE_NETWORK" ]] && command+=("$UFW_DOCKER_RULE_NETWORK")

        printf 'reload: '
        printf '%q ' "${command[@]}"
        printf '\n'
        if [[ "$dry_run" != "1" ]] && ! "${command[@]}"; then
            failures+=("failed: $key")
        fi
    done

    if (( ${#failures[@]} > 0 )); then
        printf '%s\n' "${failures[@]}" >&2
        return 1
    fi
    return 0
}
