#!/usr/bin/env bash
# shellcheck shell=bash
# System, Swarm, installation and diagnostics menus for ufw-docker-menu.

confirm_exact() {
    local keyword="${1:?missing keyword}"
    local prompt="${2:-危险操作}"
    local answer
    [[ "$TESTING" == "1" ]] && return 0
    printf '%s%s%s\n' "$C_RED" "$prompt" "$C_RESET"
    printf '请输入 %s 继续：' "$keyword"
    read -r answer || return 1
    [[ "$answer" == "$keyword" ]]
}

run_mutating_cmd() {
    require_root "$@" || return 1
    printf '\n%s即将执行：%s\n' "$C_BOLD" "$C_RESET"
    print_cmd "$@"
    confirm "确认执行？" || {
        info "已取消。"
        return 0
    }
    run_cmd "$@"
}

install_check_menu() {
    local choice
    require_core || { pause_screen; return; }
    while true; do
        clear_screen
        render_banner
        separator
        say "  1. 检查规则（默认私有网段）"
        say "  2. 检查规则（自动检测 Docker 子网）"
        say "  3. 安装规则（默认私有网段）"
        say "  4. 安装规则（自动检测 Docker 子网）"
        say "  5. 安装规则 + 系统命令/Man page/自动重载服务"
        say "  0. 返回"
        separator
        printf '选择：'
        read -r choice || choice=0
        case "$choice" in
            1) require_root "$@" && core_exec check; pause_screen ;;
            2) require_root "$@" && core_exec check --docker-subnets; pause_screen ;;
            3) require_root "$@" && run_mutating_cmd "$CORE_BIN" install; pause_screen ;;
            4) require_root "$@" && run_mutating_cmd "$CORE_BIN" install --docker-subnets; pause_screen ;;
            5) require_root "$@" && run_mutating_cmd "$CORE_BIN" install --system; pause_screen ;;
            0) return ;;
            *) warn "无效选择。"; pause_screen ;;
        esac
    done
}

service_menu() {
    local choice
    while true; do
        clear_screen
        render_banner
        separator
        printf '当前服务状态：%s\n\n' "$(service_state)"
        say "  1. 安装自动重载服务"
        say "  2. 强制重装自动重载服务"
        say "  3. 查看 systemd 状态"
        say "  4. 启动服务"
        say "  5. 停止服务"
        say "  6. 重启服务"
        say "  7. 查看最近日志"
        say "  0. 返回"
        separator
        printf '选择：'
        read -r choice || choice=0
        case "$choice" in
            1)
                require_core && require_root "$@" &&
                    run_mutating_cmd "$CORE_BIN" install-service
                pause_screen
                ;;
            2)
                require_core && require_root "$@" &&
                    run_mutating_cmd "$CORE_BIN" install-service --force
                pause_screen
                ;;
            3)
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl status "$SERVICE_NAME" --no-pager 2>&1 || true
                else
                    warn "当前系统不是 systemd。"
                fi
                pause_screen
                ;;
            4|5|6)
                if ! command -v systemctl >/dev/null 2>&1; then
                    warn "当前系统不是 systemd。"
                else
                    local action
                    case "$choice" in
                        4) action=start ;;
                        5) action=stop ;;
                        6) action=restart ;;
                    esac
                    require_root "$@" && run_mutating_cmd systemctl "$action" "$SERVICE_NAME"
                fi
                pause_screen
                ;;
            7)
                if command -v journalctl >/dev/null 2>&1; then
                    journalctl -u "$SERVICE_NAME" -n 100 --no-pager 2>&1 || true
                else
                    warn "journalctl 不可用。"
                fi
                pause_screen
                ;;
            0) return ;;
            *) warn "无效选择。"; pause_screen ;;
        esac
    done
}

load_swarm_services() {
    require_command docker || return 1
    docker service ls --format '{{.Name}}\t{{.Image}}\t{{.Replicas}}' 2>/dev/null
}

select_swarm_service() {
    local -a rows=()
    local row choice idx name image replicas
    mapfile -t rows < <(load_swarm_services)
    (( ${#rows[@]} > 0 )) || {
        warn "未检测到 Docker Swarm 服务，或当前节点不是 manager。"
        return 1
    }
    printf '\n%s请选择 Swarm 服务：%s\n' "$C_BOLD" "$C_RESET"
    idx=1
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r name image replicas <<< "$row"
        printf '  %s%2d.%s %-28s %-30s %s\n' \
            "$C_GREEN" "$idx" "$C_RESET" "$name" "$image" "$replicas"
        ((idx++))
    done
    say "  0. 返回"
    printf '选择：'
    read -r choice || return 1
    [[ "$choice" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#rows[@]} )) || return 1
    row="${rows[choice-1]}"
    IFS=$'\t' read -r SELECTED_SERVICE _ <<< "$row"
}

swarm_service_ports() {
    docker service inspect "${1:?missing service}" --format \
        '{{range .Endpoint.Spec.Ports}}{{.TargetPort}}/{{.Protocol}}{{"|"}}{{.PublishedPort}}{{"\n"}}{{end}}' \
        2>/dev/null | sed '/^[[:space:]]*$/d'
}

select_swarm_service_port() {
    local service="${1:?missing service}"
    local -a rows=()
    local row choice idx target published
    mapfile -t rows < <(swarm_service_ports "$service")
    (( ${#rows[@]} > 0 )) || {
        warn "该 Swarm 服务没有发布端口。"
        return 1
    }
    printf '\n%s请选择 TargetPort：%s\n' "$C_BOLD" "$C_RESET"
    idx=1
    for row in "${rows[@]}"; do
        IFS='|' read -r target published <<< "$row"
        printf '  %s%2d.%s %-12s published=%s\n' \
            "$C_GREEN" "$idx" "$C_RESET" "$target" "$published"
        ((idx++))
    done
    say "  0. 返回"
    printf '选择：'
    read -r choice || return 1
    [[ "$choice" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#rows[@]} )) || return 1
    IFS='|' read -r SELECTED_SERVICE_PORT _ <<< "${rows[choice-1]}"
}

swarm_menu() {
    local choice
    require_core || { pause_screen; return; }
    while true; do
        clear_screen
        render_banner
        separator
        say "  1. 列出 Swarm 服务"
        say "  2. 放行 Swarm 服务端口"
        say "  3. 删除 Swarm 服务全部放行"
        say "  4. 删除 Swarm 服务指定端口放行"
        say "  5. 查看 ufw-docker-agent"
        say "  0. 返回"
        separator
        printf '选择：'
        read -r choice || choice=0
        case "$choice" in
            1) docker service ls 2>&1 || true; pause_screen ;;
            2)
                select_swarm_service || { pause_screen; continue; }
                select_swarm_service_port "$SELECTED_SERVICE" || { pause_screen; continue; }
                require_root "$@" && run_mutating_cmd \
                    "$CORE_BIN" service allow "$SELECTED_SERVICE" "$SELECTED_SERVICE_PORT"
                pause_screen
                ;;
            3)
                select_swarm_service || { pause_screen; continue; }
                require_root "$@" && run_mutating_cmd \
                    "$CORE_BIN" service delete allow "$SELECTED_SERVICE"
                pause_screen
                ;;
            4)
                select_swarm_service || { pause_screen; continue; }
                select_swarm_service_port "$SELECTED_SERVICE" || { pause_screen; continue; }
                require_root "$@" && run_mutating_cmd \
                    "$CORE_BIN" service delete allow "$SELECTED_SERVICE" "$SELECTED_SERVICE_PORT"
                pause_screen
                ;;
            5)
                docker service inspect ufw-docker-agent 2>&1 ||
                    docker ps --filter 'name=ufw-docker-agent' 2>&1 || true
                pause_screen
                ;;
            0) return ;;
            *) warn "无效选择。"; pause_screen ;;
        esac
    done
}

read_custom_subnets() {
    local input
    printf '请输入 CIDR，多个以空格分隔：'
    read -r input || return 1
    read -r -a CUSTOM_SUBNETS <<< "$input"
    (( ${#CUSTOM_SUBNETS[@]} > 0 )) || return 1
    validate_cidr_list "${CUSTOM_SUBNETS[@]}"
}

subnet_menu() {
    local choice
    local -a CUSTOM_SUBNETS=()
    require_core || { pause_screen; return; }
    while true; do
        clear_screen
        render_banner
        separator
        say "  1. 查看 Docker 网络与子网"
        say "  2. Check：自动检测全部 Docker 子网"
        say "  3. Install：自动检测全部 Docker 子网"
        say "  4. Check：自定义允许子网"
        say "  5. Install：自定义允许子网"
        say "  0. 返回"
        separator
        printf '选择：'
        read -r choice || choice=0
        case "$choice" in
            1) show_networks; pause_screen ;;
            2) require_root "$@" && core_exec check --docker-subnets; pause_screen ;;
            3) require_root "$@" && run_mutating_cmd "$CORE_BIN" install --docker-subnets; pause_screen ;;
            4|5)
                CUSTOM_SUBNETS=()
                if ! read_custom_subnets; then
                    error "CIDR 格式无效。"
                    pause_screen
                    continue
                fi
                if [[ "$choice" == "4" ]]; then
                    require_root "$@" && core_exec check --docker-subnets "${CUSTOM_SUBNETS[@]}"
                else
                    require_root "$@" && run_mutating_cmd \
                        "$CORE_BIN" install --docker-subnets "${CUSTOM_SUBNETS[@]}"
                fi
                pause_screen
                ;;
            0) return ;;
            *) warn "无效选择。"; pause_screen ;;
        esac
    done
}

run_helper_readonly() {
    local helper="${1:?missing helper}"
    shift || true
    local path
    path="$(resolve_helper "$helper")" || {
        error "未找到辅助脚本：$helper"
        return 1
    }
    "$path" "$@"
}

run_helper_mutating() {
    local helper="${1:?missing helper}"
    shift || true
    local path
    path="$(resolve_helper "$helper")" || {
        error "未找到辅助脚本：$helper"
        return 1
    }
    require_root "$@" || return 1
    run_mutating_cmd "$path" "$@"
}

show_environment_report() {
    printf '%s系统环境%s\n' "$C_BOLD" "$C_RESET"
    printf 'OS: %s\n' "$(os_pretty_name)"
    printf 'Kernel: %s\n' "$(uname -srmo 2>/dev/null || uname -a)"
    printf 'Bash: %s\n' "$BASH_VERSION"
    printf 'UFW: %s\n' "$(ufw_state)"
    printf 'Docker: %s\n' "$(docker_state)"
    printf 'iptables: %s\n' "$(iptables_backend)"
    printf 'ufw-docker service: %s\n' "$(service_state)"
    if resolve_core >/dev/null; then
        printf 'Core: %s\n' "$CORE_BIN"
    fi
    printf '\nDocker networks:\n'
    docker network ls 2>&1 || true
    printf '\nManaged rules:\n'
    managed_rule_lines 2>&1 || true
}

raw_ufw_command() {
    local input
    local -a args=()
    printf '请输入 UFW 参数（例如：status verbose）：'
    read -r input || return 1
    [[ -n "$input" ]] || return 1
    read -r -a args <<< "$input"
    warn "高级入口只按参数数组执行，不支持管道、重定向、命令替换。"
    require_root "$@" || return 1
    run_mutating_cmd ufw "${args[@]}"
}

diagnostic_menu() {
    local choice
    while true; do
        clear_screen
        render_banner
        separator
        say "  1. 查看 UFW verbose 状态"
        say "  2. 查看 IPv4 DOCKER-USER 链"
        say "  3. 查看 IPv6 DOCKER-USER 链"
        say "  4. 递归打印 IPv4 iptables 规则"
        say "  5. 递归打印 IPv6 iptables 规则"
        say "  6. 开启 IPv4 packet trace（高级）"
        say "  7. 移除 IPv4 packet trace"
        say "  8. 开启 IPv6 packet trace（高级）"
        say "  9. 移除 IPv6 packet trace"
        say " 10. 查看最近 100 行 UFW 日志"
        say " 11. 输出环境诊断报告"
        say " 12. 高级 UFW 原始命令"
        say "  0. 返回"
        separator
        printf '选择：'
        read -r choice || choice=0
        case "$choice" in
            1) ufw status verbose 2>&1 || true; pause_screen ;;
            2) iptables -n -L DOCKER-USER 2>&1 || true; pause_screen ;;
            3) ip6tables -n -L DOCKER-USER 2>&1 || true; pause_screen ;;
            4) require_root "$@" && run_helper_readonly print-iptables.sh; pause_screen ;;
            5) require_root "$@" && run_helper_readonly print-ip6tables.sh; pause_screen ;;
            6) run_helper_mutating trace-iptables.sh add; pause_screen ;;
            7) run_helper_mutating trace-iptables.sh remove; pause_screen ;;
            8) run_helper_mutating trace-ip6tables.sh add; pause_screen ;;
            9) run_helper_mutating trace-ip6tables.sh remove; pause_screen ;;
            10)
                if [[ -r /var/log/ufw.log ]]; then
                    tail -n 100 /var/log/ufw.log
                elif command -v journalctl >/dev/null 2>&1; then
                    journalctl -u ufw -n 100 --no-pager 2>&1 || true
                else
                    warn "无法读取 UFW 日志。"
                fi
                pause_screen
                ;;
            11) show_environment_report; pause_screen ;;
            12) raw_ufw_command; pause_screen ;;
            0) return ;;
            *) warn "无效选择。"; pause_screen ;;
        esac
    done
}

show_help_page() {
    clear_screen
    render_banner
    separator
    cat <<EOF
本菜单是 ufw-docker 的交互前端，不重新实现核心防火墙规则。

设计原则：
  - 普通容器规则通过 ufw-docker allow/list/delete/reload 执行。
  - 来源 IP/CIDR 放行通过 ufw-docker allow-ip 执行。
  - 所有修改命令执行前展示最终命令并确认。
  - 不使用 eval，不自动执行 ufw enable，不静默重启 UFW。
  - ufw-docker 使用容器端口，不是宿主机映射端口。

项目：
  $PROJECT_URL

文档：
  ${SCRIPT_DIR}/MENU.md（仓库运行）
  ${INSTALL_DOC_DIR}/MENU.md（系统安装）
EOF
    pause_screen
}

check_updates() {
    clear_screen
    render_banner
    separator
    printf '当前菜单版本：%s\n' "$MENU_VERSION"
    local remote=""
    if command -v curl >/dev/null 2>&1; then
        remote="$(curl -fsSL --max-time 5 "$UPDATE_VERSION_URL" 2>/dev/null | head -n 1 || true)"
    elif command -v wget >/dev/null 2>&1; then
        remote="$(wget -qO- --timeout=5 "$UPDATE_VERSION_URL" 2>/dev/null | head -n 1 || true)"
    fi
    if [[ -z "$remote" ]]; then
        warn "无法获取远端版本；不会自动覆盖本机脚本。"
    elif [[ "$remote" == "$MENU_VERSION" ]]; then
        success "当前已经是最新版本。"
    else
        info "远端版本：$remote"
        warn "当前仅提供安全检查，不执行 root 自动下载/覆盖。"
    fi
    pause_screen
}

install_menu_command() {
    require_root "$@" || return 1
    local source_modules="$MENU_MODULE_DIR"
    mkdir -p "$INSTALL_MODULE_DIR" "$INSTALL_DOC_DIR" "$INSTALL_HELPER_DIR"
    install -m 0755 "$SCRIPT_PATH" "$INSTALL_BIN"
    local module
    for module in common validation ui docker rules system app; do
        install -m 0644 "$source_modules/$module.sh" "$INSTALL_MODULE_DIR/$module.sh"
    done
    ln -sfn "$INSTALL_BIN" "$INSTALL_ALIAS"
    [[ -r "$SCRIPT_DIR/MENU.md" ]] && install -m 0644 "$SCRIPT_DIR/MENU.md" "$INSTALL_DOC_DIR/MENU.md"
    [[ -r "$SCRIPT_DIR/VERSION" ]] && install -m 0644 "$SCRIPT_DIR/VERSION" "$INSTALL_DOC_DIR/VERSION"
    local helper
    for helper in print-iptables.sh print-ip6tables.sh trace-iptables.sh trace-ip6tables.sh; do
        if [[ -r "$SCRIPT_DIR/$helper" ]]; then
            install -m 0755 "$SCRIPT_DIR/$helper" "$INSTALL_HELPER_DIR/$helper"
        fi
    done
    success "菜单已安装：$INSTALL_BIN"
    success "快捷命令：$INSTALL_ALIAS"
}

uninstall_menu_command() {
    require_root "$@" || return 1
    rm -f "$INSTALL_ALIAS" "$INSTALL_BIN"
    rm -rf "$INSTALL_MODULE_DIR" "$INSTALL_DOC_DIR" "$INSTALL_HELPER_DIR"
    success "菜单组件已卸载。"
}

uninstall_core_menu() {
    clear_screen
    render_banner
    require_core || { pause_screen; return; }
    if ! confirm_exact "UNINSTALL" \
        "该操作会卸载 ufw-docker 系统安装、UFW 规则、Man page 和 systemd 服务。"; then
        info "已取消卸载。"
        pause_screen
        return
    fi
    require_root "$@" || { pause_screen; return; }
    print_cmd "$CORE_BIN" uninstall
    run_cmd "$CORE_BIN" uninstall || error "核心卸载失败。"
    pause_screen
}
