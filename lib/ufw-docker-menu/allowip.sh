#!/usr/bin/env bash
# shellcheck shell=bash
# Address-family-safe source IP/CIDR handling for the interactive menu.

validate_source_family_for_scope() {
    local source="$1"
    local container="$2"
    local network="$3"
    local family has_v4 has_v6
    family="$(ip_family "$source")"
    read -r has_v4 has_v6 < <(selected_scope_address_families "$container" "$network")

    if [[ "$family" == "4" ]]; then
        (( has_v4 == 1 )) || {
            error "所选 Docker 网络没有 IPv4 目标地址。"
            return 1
        }
        if (( has_v6 == 1 )); then
            info "检测到双栈目标；IPv4 来源只会写入 IPv4 容器地址，IPv6 地址会自动跳过。"
        fi
    else
        (( has_v6 == 1 )) || {
            error "所选 Docker 网络没有 IPv6 目标地址。"
            return 1
        }
        if (( has_v4 == 1 )); then
            info "检测到双栈目标；IPv6 来源只会写入 IPv6 容器地址，IPv4 地址会自动跳过。"
        fi
    fi
    return 0
}

menu_apply_source_rule() {
    local source="${1:?missing source}"
    local container="${2:?missing container}"
    local port_proto="${3:-}"
    local network="${4:-}"
    local port="" proto=""

    lifecycle_available || {
        error "规则生命周期库不可用，无法安全添加来源 IP/CIDR 规则。请重新安装菜单。"
        return 1
    }
    declare -F ufw_docker_apply_source_rule >/dev/null 2>&1 || {
        error "当前规则生命周期库版本过旧，缺少双栈安全写入功能。请先更新菜单。"
        return 1
    }

    if [[ -n "$port_proto" ]]; then
        port="${port_proto%/*}"
        proto="${port_proto#*/}"
    fi

    printf '\n%s即将写入以下同地址族规则：%s\n' "$C_BOLD" "$C_RESET"
    if ! ufw_docker_apply_source_rule "$source" "$container" "$port" "$proto" "$network" 1; then
        error "没有生成可执行的同地址族规则。"
        return 1
    fi

    [[ -n "$port_proto" ]] || warn "该操作将处理容器全部已发布端口，但只写入与来源 IP 同地址族的目标地址。"
    confirm "确认添加以上规则？" || {
        info "已取消。"
        return 0
    }

    if [[ "$DRY_RUN" == "1" ]]; then
        info "DRY-RUN：未修改 UFW。"
        return 0
    fi

    if ufw_docker_apply_source_rule "$source" "$container" "$port" "$proto" "$network" 0; then
        success "来源 IP/CIDR 规则处理完成。"
        return 0
    fi
    error "来源 IP/CIDR 规则处理失败，请查看上方输出。"
    return 1
}

# Override rules.sh so source-restricted rules no longer call the legacy core
# allow-ip path on dual-stack targets. Ordinary allow rules still use the core.
apply_container_rule() {
    local mode="${1:-allow}"
    local source=""
    local -a cmd=()

    clear_screen
    render_banner
    separator
    select_container || { pause_screen; return; }
    select_container_port "$SELECTED_CONTAINER" || { pause_screen; return; }
    select_container_network "$SELECTED_CONTAINER" || { pause_screen; return; }

    if [[ "$mode" == "allow-ip" ]]; then
        printf '\n请输入允许访问的来源 IP 或 CIDR：'
        read -r source || source=""
        validate_ip_or_cidr "$source" || {
            error "IP/CIDR 格式无效：$source"
            pause_screen
            return
        }
        validate_source_family_for_scope \
            "$source" "$SELECTED_CONTAINER" "$SELECTED_NETWORK" || {
            pause_screen
            return
        }
        menu_apply_source_rule \
            "$source" "$SELECTED_CONTAINER" "$SELECTED_PORT_PROTO" "$SELECTED_NETWORK"
        pause_screen
        return
    fi

    require_core || { pause_screen; return; }
    cmd=("$CORE_BIN" allow "$SELECTED_CONTAINER")
    [[ -n "$SELECTED_PORT_PROTO" ]] && cmd+=("$SELECTED_PORT_PROTO")
    [[ -n "$SELECTED_NETWORK" ]] && cmd+=("$SELECTED_NETWORK")

    printf '\n%s即将执行：%s\n' "$C_BOLD" "$C_RESET"
    print_cmd "${cmd[@]}"
    [[ -n "$SELECTED_PORT_PROTO" ]] || warn "该操作将放行容器的全部已发布端口。"

    if confirm "确认添加规则？"; then
        run_cmd "${cmd[@]}" && success "规则处理完成。" ||
            error "规则处理失败，请查看上方输出。"
    else
        info "已取消。"
    fi
    pause_screen
}
