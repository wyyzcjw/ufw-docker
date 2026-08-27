#!/usr/bin/env bash
# shellcheck shell=bash
# Generated module for ufw-docker-menu.

load_running_containers() {
    require_command docker || return 1
    docker info >/dev/null 2>&1 || {
        die "Docker daemon 不可用。"
        return 1
    }
    docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
}

select_container() {
    local -a rows=()
    local row choice idx name image status ports
    mapfile -t rows < <(load_running_containers)
    (( ${#rows[@]} > 0 )) || {
        warn "没有正在运行的容器。"
        return 1
    }

    printf '\n%s请选择容器：%s\n' "$C_BOLD" "$C_RESET"
    idx=1
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r name image status ports <<< "$row"
        printf '  %s%2d.%s %-24s  %-28s  %s\n' \
            "$C_GREEN" "$idx" "$C_RESET" "$name" "$image" "${ports:--}"
        printf '      %s%s%s\n' "$C_GRAY" "$status" "$C_RESET"
        ((idx++))
    done
    say "  0. 返回"
    printf '选择：'
    read -r choice || return 1
    [[ "$choice" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#rows[@]} )) || return 1

    row="${rows[choice-1]}"
    IFS=$'\t' read -r SELECTED_CONTAINER _ <<< "$row"
    [[ -n "$SELECTED_CONTAINER" ]]
}

container_published_ports() {
    docker inspect --format \
        '{{range $p,$bindings := .NetworkSettings.Ports}}{{if $bindings}}{{$p}}{{"\n"}}{{end}}{{end}}' \
        "${1:?missing container}" 2>/dev/null | sed '/^[[:space:]]*$/d' | sort -u
}

port_bindings() {
    docker port "${1:?missing container}" "${2:?missing port}" 2>/dev/null |
        paste -sd ', ' - || true
}

select_container_port() {
    local container="${1:?missing container}"
    local -a ports=()
    local choice idx item binding
    mapfile -t ports < <(container_published_ports "$container")
    (( ${#ports[@]} > 0 )) || {
        warn "容器 \"$container\" 没有已发布端口。"
        return 1
    }

    printf '\n%s请选择容器端口：%s\n' "$C_BOLD" "$C_RESET"
    printf '  %s1.%s 全部已发布端口\n' "$C_MAGENTA" "$C_RESET"
    idx=2
    for item in "${ports[@]}"; do
        binding="$(port_bindings "$container" "$item")"
        printf '  %s%2d.%s %-12s  主机映射：%s\n' \
            "$C_GREEN" "$idx" "$C_RESET" "$item" "${binding:--}"
        ((idx++))
    done
    say "  0. 返回"
    printf '选择：'
    read -r choice || return 1
    [[ "$choice" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#ports[@]} + 1 )) || return 1

    if (( choice == 1 )); then
        SELECTED_PORT_PROTO=""
    else
        SELECTED_PORT_PROTO="${ports[choice-2]}"
    fi
}

container_networks() {
    docker inspect --format \
        '{{range $name,$net := .NetworkSettings.Networks}}{{$name}}{{"|"}}{{$net.IPAddress}}{{"|"}}{{$net.GlobalIPv6Address}}{{"\n"}}{{end}}' \
        "${1:?missing container}" 2>/dev/null | sed '/^[[:space:]]*$/d'
}

select_container_network() {
    local container="${1:?missing container}"
    local -a rows=()
    local choice idx row name ipv4 ipv6
    mapfile -t rows < <(container_networks "$container")
    (( ${#rows[@]} > 0 )) || {
        warn "未读取到容器网络。"
        return 1
    }

    printf '\n%s请选择 Docker 网络：%s\n' "$C_BOLD" "$C_RESET"
    printf '  %s1.%s 全部已连接网络\n' "$C_MAGENTA" "$C_RESET"
    idx=2
    for row in "${rows[@]}"; do
        IFS='|' read -r name ipv4 ipv6 <<< "$row"
        printf '  %s%2d.%s %-24s IPv4=%-16s IPv6=%s\n' \
            "$C_GREEN" "$idx" "$C_RESET" "$name" "${ipv4:--}" "${ipv6:--}"
        ((idx++))
    done
    say "  0. 返回"
    printf '选择：'
    read -r choice || return 1
    [[ "$choice" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#rows[@]} + 1 )) || return 1

    if (( choice == 1 )); then
        SELECTED_NETWORK=""
    else
        row="${rows[choice-2]}"
        IFS='|' read -r SELECTED_NETWORK _ <<< "$row"
    fi
}

selected_scope_address_families() {
    local container="$1"
    local network="$2"
    local name ipv4 ipv6 has_v4=0 has_v6=0
    while IFS='|' read -r name ipv4 ipv6; do
        [[ -z "$network" || "$name" == "$network" ]] || continue
        [[ -n "$ipv4" ]] && has_v4=1
        [[ -n "$ipv6" ]] && has_v6=1
    done < <(container_networks "$container")
    printf '%s %s\n' "$has_v4" "$has_v6"
}

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
        (( has_v6 == 0 )) || {
            error "所选范围同时包含 IPv6 目标地址。当前核心 allow-ip 会遍历全部地址，"
            error "为避免地址族不匹配导致部分规则写入，本菜单已阻止该操作。请选择仅 IPv4 的网络。"
            return 1
        }
    else
        (( has_v6 == 1 )) || {
            error "所选 Docker 网络没有 IPv6 目标地址。"
            return 1
        }
        (( has_v4 == 0 )) || {
            error "所选范围同时包含 IPv4 目标地址。当前核心 allow-ip 会遍历全部地址，"
            error "为避免地址族不匹配导致部分规则写入，本菜单已阻止该操作。请选择仅 IPv6 的网络。"
            return 1
        }
    fi
}

show_container_details() {
    select_container || return 1
    clear_screen
    printf '%s容器：%s%s%s\n' "$C_BOLD" "$C_CYAN" "$SELECTED_CONTAINER" "$C_RESET"
    separator
    docker inspect --format \
        'ID: {{.Id}}{{"\n"}}镜像: {{.Config.Image}}{{"\n"}}状态: {{.State.Status}}{{"\n"}}启动时间: {{.State.StartedAt}}' \
        "$SELECTED_CONTAINER" 2>/dev/null || true

    printf '\n%s已发布端口%s\n' "$C_BOLD" "$C_RESET"
    local port binding
    while IFS= read -r port; do
        [[ -n "$port" ]] || continue
        binding="$(port_bindings "$SELECTED_CONTAINER" "$port")"
        printf '  %-12s -> %s\n' "$port" "${binding:--}"
    done < <(container_published_ports "$SELECTED_CONTAINER")

    printf '\n%s网络与地址%s\n' "$C_BOLD" "$C_RESET"
    while IFS='|' read -r name ipv4 ipv6; do
        printf '  %-24s IPv4=%-16s IPv6=%s\n' "$name" "${ipv4:--}" "${ipv6:--}"
    done < <(container_networks "$SELECTED_CONTAINER")

    printf '\n%s关联规则%s\n' "$C_BOLD" "$C_RESET"
    show_managed_rules "$SELECTED_CONTAINER"
}

show_networks() {
    require_command docker || return 1
    docker network ls
    printf '\n'
    local net
    while IFS= read -r net; do
        [[ -n "$net" ]] || continue
        docker network inspect "$net" --format \
            '{{.Name}}{{range .IPAM.Config}}{{"\t"}}{{.Subnet}}{{"\t"}}{{.Gateway}}{{end}}' \
            2>/dev/null || true
    done < <(docker network ls -q)
}

container_info_menu() {
    local choice
    while true; do
        clear_screen
        render_banner
        separator
        say "  1. 查看运行中容器"
        say "  2. 查看指定容器详情"
        say "  3. 查看 Docker 网络与子网"
        say "  4. 查看 Docker 端口映射"
        say "  0. 返回"
        separator
        printf '选择：'
        read -r choice || choice=0
        case "$choice" in
            1) clear_screen; load_running_containers || true; pause_screen ;;
            2) show_container_details || true; pause_screen ;;
            3) clear_screen; show_networks || true; pause_screen ;;
            4)
                clear_screen
                docker ps --format 'table {{.Names}}\t{{.Ports}}' || true
                pause_screen
                ;;
            0) return ;;
            *) warn "无效选择。" ; pause_screen ;;
        esac
    done
}
