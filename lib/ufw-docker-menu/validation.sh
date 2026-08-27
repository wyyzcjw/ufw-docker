#!/usr/bin/env bash
# shellcheck shell=bash
# Generated module for ufw-docker-menu.

validate_port_proto() {
    local value="${1:-}"
    [[ -z "$value" || "$value" =~ ^([1-9][0-9]{0,4})/(tcp|udp)$ ]] || return 1
    if [[ -n "$value" ]]; then
        local port="${value%/*}"
        (( port >= 1 && port <= 65535 )) || return 1
    fi
}

validate_ipv4_address() {
    local address="${1:-}"
    local -a octets=()
    local octet
    IFS='.' read -r -a octets <<< "$address"
    (( ${#octets[@]} == 4 )) || return 1
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
        (( 10#$octet <= 255 )) || return 1
    done
}

validate_ipv6_groups() {
    local groups_string="${1:-}"
    local -a groups=()
    local group
    [[ -z "$groups_string" ]] && return 0
    IFS=':' read -r -a groups <<< "$groups_string"
    for group in "${groups[@]}"; do
        [[ "$group" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
    done
}

count_ipv6_groups() {
    local groups_string="${1:-}"
    local -a groups=()
    [[ -z "$groups_string" ]] && { printf '0\n'; return 0; }
    IFS=':' read -r -a groups <<< "$groups_string"
    printf '%s\n' "${#groups[@]}"
}

validate_ipv6_address() {
    local address="${1:-}"
    local left right ipv4_tail left_count right_count
    [[ -n "$address" && "$address" == *:* ]] || return 1
    [[ "$address" != *:::* ]] || return 1
    [[ "$address" != :* || "$address" == ::* ]] || return 1
    [[ "$address" != *: || "$address" == *:: ]] || return 1

    if [[ "$address" == *.* ]]; then
        ipv4_tail="${address##*:}"
        validate_ipv4_address "$ipv4_tail" || return 1
        address="${address%:*}:0:0"
    fi

    if [[ "$address" == *::* ]]; then
        [[ "${address#*::}" != *::* ]] || return 1
        left="${address%%::*}"
        right="${address#*::}"
        validate_ipv6_groups "$left" || return 1
        validate_ipv6_groups "$right" || return 1
        left_count="$(count_ipv6_groups "$left")"
        right_count="$(count_ipv6_groups "$right")"
        (( left_count + right_count < 8 )) || return 1
    else
        validate_ipv6_groups "$address" || return 1
        [[ "$(count_ipv6_groups "$address")" == "8" ]] || return 1
    fi
}

validate_ip_or_cidr() {
    local value="${1:-}"
    local address prefix=""
    [[ -n "$value" ]] || return 1
    [[ "$value" != *[[:space:]]* ]] || return 1
    [[ "$value" =~ ^[0-9A-Fa-f:./]+$ ]] || return 1
    [[ "${value#*/}" != */* ]] || return 1

    if [[ "${UFW_DOCKER_MENU_NO_PYTHON:-0}" != "1" ]] && command -v python3 >/dev/null 2>&1; then
        python3 - "$value" >/dev/null 2>&1 <<'PY'
import ipaddress
import sys

value = sys.argv[1]
try:
    if "/" in value:
        ipaddress.ip_network(value, strict=False)
    else:
        ipaddress.ip_address(value)
except ValueError:
    raise SystemExit(1)
PY
        return $?
    fi

    address="${value%%/*}"
    if [[ "$value" == */* ]]; then
        prefix="${value#*/}"
        [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
    fi

    if [[ "$address" == *:* ]]; then
        validate_ipv6_address "$address" || return 1
        [[ -z "$prefix" ]] || (( prefix >= 0 && prefix <= 128 ))
    else
        validate_ipv4_address "$address" || return 1
        [[ -z "$prefix" ]] || (( prefix >= 0 && prefix <= 32 ))
    fi
}

ip_family() {
    [[ "${1:-}" == *:* ]] && printf '6\n' || printf '4\n'
}

validate_cidr_list() {
    local item
    (( $# > 0 )) || return 1
    for item in "$@"; do
        validate_ip_or_cidr "$item" || return 1
        [[ "$item" == */* ]] || return 1
    done
}

parse_rule_comment() {
    local comment="${1:-}"
    local -a tokens=()
    local token

    PARSED_INSTANCE=""
    PARSED_PORT=""
    PARSED_PROTO=""
    PARSED_NETWORK=""
    PARSED_SOURCE=""
    PARSED_IS_V6="0"

    comment="${comment#\# allow }"
    comment="${comment#allow }"
    read -r -a tokens <<< "$comment"
    (( ${#tokens[@]} > 0 )) || return 1

    PARSED_INSTANCE="${tokens[0]}"
    if [[ "$PARSED_INSTANCE" == */v6 ]]; then
        PARSED_INSTANCE="${PARSED_INSTANCE%/v6}"
        PARSED_IS_V6="1"
    fi
    [[ -n "$PARSED_INSTANCE" ]] || return 1

    for token in "${tokens[@]:1}"; do
        if [[ "$token" =~ ^([0-9]+)/(tcp|udp)$ ]]; then
            PARSED_PORT="${BASH_REMATCH[1]}"
            PARSED_PROTO="${BASH_REMATCH[2]}"
        elif [[ "$token" == from:* ]]; then
            PARSED_SOURCE="${token#from:}"
        elif [[ -z "$PARSED_NETWORK" ]]; then
            PARSED_NETWORK="$token"
        fi
    done
}

normalized_rule_key() {
    parse_rule_comment "${1:-}" || return 1
    printf '%s|%s|%s|%s|%s\n' \
        "$PARSED_INSTANCE" "$PARSED_PORT" "$PARSED_PROTO" \
        "$PARSED_NETWORK" "$PARSED_SOURCE"
}
