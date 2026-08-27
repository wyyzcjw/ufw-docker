#!/usr/bin/env bash
# shellcheck shell=bash
# Generated module for ufw-docker-menu.

managed_rule_lines() {
    require_command ufw || return 1
    ufw status numbered 2>/dev/null | grep -F '# allow ' || true
}

managed_rule_comments() {
    managed_rule_lines | sed -n 's/.*# allow /allow /p'
}

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
    fi

    require_core || { pause_screen; return; }
    if [[ "$mode" == "allow-ip" ]]; then
        cmd=("$CORE_BIN" allow-ip "$source" "$SELECTED_CONTAINER")
    else
        cmd=("$CORE_BIN" allow "$SELECTED_CONTAINER")
    fi
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

show_managed_rules() {
    local filter="${1:-}"
    local line found=0
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if [[ -n "$filter" ]] && ! grep -Fq "# allow $filter" <<< "$line"; then
            continue
        fi
        printf '%s\n' "$line"
        found=1
    done < <(managed_rule_lines)
    (( found == 1 )) || say "没有匹配的 UFW-Docker 规则。"
}

core_filtered_list() {
    local container port_proto network
    local -a cmd=()
    require_core || return 1

    printf '容器名称或 ID：'
    read -r container || container=""
    [[ -n "$container" ]] || { error "容器名称不能为空。"; return 1; }

    printf '容器端口/协议（可留空，例如 80/tcp）：'
    read -r port_proto || port_proto=""
    validate_port_proto "$port_proto" || { error "端口格式无效。"; return 1; }

    printf 'Docker 网络名称（可留空）：'
    read -r network || network=""
    if [[ -n "$network" && -z "$port_proto" ]]; then
        error "核心 CLI 不能在省略端口时单独指定网络；请同时输入端口/协议。"
        return 1
    fi

    cmd=("$CORE_BIN" list "$container")
    [[ -n "$port_proto" ]] && cmd+=("$port_proto")
    [[ -n "$network" ]] && cmd+=("$network")
    run_cmd "${cmd[@]}" || true
}

core_filtered_delete() {
    local container port_proto network
    local -a cmd=()
    require_core || return 1

    printf '容器名称或 ID：'
    read -r container || container=""
    [[ -n "$container" ]] || { error "容器名称不能为空。"; return 1; }

    printf '容器端口/协议（可留空，例如 80/tcp）：'
    read -r port_proto || port_proto=""
    validate_port_proto "$port_proto" || { error "端口格式无效。"; return 1; }

    printf 'Docker 网络名称（可留空）：'
    read -r network || network=""

    cmd=("$CORE_BIN" delete allow "$container")
    [[ -n "$port_proto" ]] && cmd+=("$port_proto")
    [[ -n "$network" ]] && cmd+=("$network")

    printf '\n%s即将执行核心删除命令：%s\n' "$C_BOLD" "$C_RESET"
    print_cmd "${cmd[@]}"
    warn "核心 delete allow 只匹配普通规则；带 from: 的来源 IP 规则请按 UFW 编号删除。"
    confirm "确认删除匹配规则？" || { info "已取消。"; return 0; }
    run_cmd "${cmd[@]}" || true
}

extract_rule_number() {
    sed -n 's/^\[[[:blank:]]*\([0-9][0-9]*\)\].*/\1/p' <<< "${1:-}"
}

delete_rules_by_numbers() {
    local input="${1:-}"
    local -a numbers=()
    local token
    input="${input//,/ }"
    read -r -a numbers <<< "$input"
    (( ${#numbers[@]} > 0 )) || return 1

    for token in "${numbers[@]}"; do
        [[ "$token" =~ ^[0-9]+$ ]] || {
            error "规则编号无效：$token"
            return 1
        }
    done

    mapfile -t numbers < <(printf '%s\n' "${numbers[@]}" | sort -rn -u)
    printf '\n%s将删除以下 UFW 规则编号：%s %s\n' \
        "$C_RED" "$C_RESET" "${numbers[*]}"
    confirm "确认删除？" || { info "已取消。"; return 0; }

    for token in "${numbers[@]}"; do
        if [[ "$DRY_RUN" == "1" ]]; then
            print_cmd ufw delete "$token"
        else
            printf 'y\n' | ufw delete "$token" ||
                warn "删除规则 $token 失败。"
        fi
    done
}

delete_container_rules() {
    select_container || return 1
    local -a matched=()
    local line number comment
    clear_screen
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        comment="$(sed -n 's/.*# allow /allow /p' <<< "$line")"
        parse_rule_comment "$comment" || continue
        [[ "$PARSED_INSTANCE" == "$SELECTED_CONTAINER" ]] || continue
        printf '%s\n' "$line"
        number="$(extract_rule_number "$line")"
        [[ -n "$number" ]] && matched+=("$number")
    done < <(managed_rule_lines)

    if (( ${#matched[@]} == 0 )); then
        warn "没有找到该容器的规则。"
    else
        delete_rules_by_numbers "${matched[*]}"
    fi
}

rules_menu() {
    local choice filter numbers
    while true; do
        clear_screen
        render_banner
        separator
        say "  1. 查看全部 UFW-Docker 规则"
        say "  2. 按容器名称快速筛选"
        say "  3. 调用核心 list 按容器/端口/网络查询"
        say "  4. 调用核心 delete allow 删除普通规则"
        say "  5. 按 UFW 编号删除任意已管理规则"
        say "  6. 删除某容器的全部已管理规则"
        say "  0. 返回"
        separator
        printf '选择：'
        read -r choice || choice=0
        case "$choice" in
            1) clear_screen; show_managed_rules; pause_screen ;;
            2)
                printf '输入容器名称：'
                read -r filter || filter=""
                clear_screen
                show_managed_rules "$filter"
                pause_screen
                ;;
            3) clear_screen; core_filtered_list; pause_screen ;;
            4) clear_screen; core_filtered_delete; pause_screen ;;
            5)
                clear_screen
                show_managed_rules
                printf '\n输入 UFW 规则编号，可用空格或逗号分隔：'
                read -r numbers || numbers=""
                delete_rules_by_numbers "$numbers"
                pause_screen
                ;;
            6) delete_container_rules; pause_screen ;;
            0) return ;;
            *) warn "无效选择。" ; pause_screen ;;
        esac
    done
}

enhanced_reload_rules() {
    local -A seen=()
    local -a comments=() failures=() cmd=()
    local comment key
    mapfile -t comments < <(managed_rule_comments)
    (( ${#comments[@]} > 0 )) || {
        info "当前没有需要重载的 UFW-Docker 规则。"
        return 0
    }

    ssh_context_warning
    warn "增强重载会解析容器、端口、网络和 from:来源 IP。"
    confirm "确认重载 ${#comments[@]} 条规则记录？" || {
        info "已取消。"
        return 0
    }
    require_core || return 1

    for comment in "${comments[@]}"; do
        key="$(normalized_rule_key "$comment" 2>/dev/null || true)"
        [[ -n "$key" ]] || { failures+=("无法解析：$comment"); continue; }
        [[ -z "${seen[$key]+x}" ]] || continue
        seen["$key"]=1
        parse_rule_comment "$comment" || { failures+=("无法解析：$comment"); continue; }

        if command -v docker >/dev/null 2>&1 &&
           docker service inspect "$PARSED_INSTANCE" >/dev/null 2>&1; then
            info "Swarm 服务规则交由 ufw-docker-agent 重建：$comment"
            continue
        fi

        if [[ -n "$PARSED_SOURCE" ]]; then
            cmd=("$CORE_BIN" allow-ip "$PARSED_SOURCE" "$PARSED_INSTANCE")
        else
            cmd=("$CORE_BIN" allow "$PARSED_INSTANCE")
        fi
        [[ -n "$PARSED_PORT" ]] && cmd+=("${PARSED_PORT}/${PARSED_PROTO}")
        [[ -n "$PARSED_NETWORK" ]] && cmd+=("$PARSED_NETWORK")

        printf '\n%s重载规则：%s\n' "$C_BOLD" "$C_RESET"
        print_cmd "${cmd[@]}"
        if [[ "$DRY_RUN" != "1" ]] && ! "${cmd[@]}"; then
            failures+=("执行失败：$comment")
        fi
    done

    if command -v docker >/dev/null 2>&1; then
        local -a agents=()
        mapfile -t agents < <(docker ps --filter 'name=ufw-docker-agent' -q 2>/dev/null || true)
        if (( ${#agents[@]} > 0 )); then
            info "触发 ufw-docker-agent 重建..."
            if [[ "$DRY_RUN" == "1" ]]; then
                print_cmd docker rm -f "${agents[@]}"
            else
                docker rm -f "${agents[@]}" >/dev/null ||
                    warn "ufw-docker-agent 重建触发失败。"
            fi
        fi
    fi

    if (( ${#failures[@]} > 0 )); then
        error "部分规则未能重载："
        printf '  - %s\n' "${failures[@]}"
        warn "失败规则未自动删除，请人工复核。"
        return 1
    fi
    success "全部规则重载完成。"
}

reload_menu() {
    local choice
    while true; do
        clear_screen
        render_banner
        separator
        say "  1. 增强重载（支持 from:来源 IP）"
        say "  2. 调用原始 ufw-docker reload"
        say "  3. 仅执行 ufw reload"
        say "  0. 返回"
        separator
        printf '选择：'
        read -r choice || choice=0
        case "$choice" in
            1) enhanced_reload_rules; pause_screen ;;
            2)
                ssh_context_warning
                confirm "确认调用原始 reload？" && core_exec reload || true
                pause_screen
                ;;
            3)
                ssh_context_warning
                confirm "确认重新加载 UFW？" && run_cmd ufw reload || true
                pause_screen
                ;;
            0) return ;;
            *) warn "无效选择。" ; pause_screen ;;
        esac
    done
}
