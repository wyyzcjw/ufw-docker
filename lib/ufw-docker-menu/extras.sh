#!/usr/bin/env bash
# shellcheck shell=bash
# Lifecycle integration, advanced core commands and installation overrides.

RULECTL_BIN="/usr/local/bin/ufw-docker-rulectl"
RULECTL_LIB="/usr/local/lib/ufw-docker/ufw-docker-rules.sh"
LIFECYCLE_LIB=""

for lifecycle_candidate in \
    "$SCRIPT_DIR/lib/ufw-docker-rules.sh" \
    "$RULECTL_LIB"; do
    if [[ -r "$lifecycle_candidate" ]]; then
        LIFECYCLE_LIB="$lifecycle_candidate"
        break
    fi
done
unset lifecycle_candidate

if [[ -n "$LIFECYCLE_LIB" ]]; then
    # shellcheck disable=SC1090
    source "$LIFECYCLE_LIB"
fi

lifecycle_available() {
    [[ -n "$LIFECYCLE_LIB" ]] && declare -F ufw_docker_parse_comment >/dev/null 2>&1
}

# Keep the menu parser and the standalone rulectl parser on exactly the same
# comment grammar. These definitions intentionally override validation.sh.
parse_rule_comment() {
    if ! lifecycle_available; then
        error "规则生命周期库不可用。"
        return 1
    fi
    ufw_docker_parse_comment "${1:-}" || return 1
    PARSED_INSTANCE="$UFW_DOCKER_RULE_INSTANCE"
    PARSED_PORT="$UFW_DOCKER_RULE_PORT"
    PARSED_PROTO="$UFW_DOCKER_RULE_PROTO"
    PARSED_NETWORK="$UFW_DOCKER_RULE_NETWORK"
    PARSED_SOURCE="$UFW_DOCKER_RULE_SOURCE"
    PARSED_IS_V6="$UFW_DOCKER_RULE_IS_V6"
}

normalized_rule_key() {
    parse_rule_comment "${1:-}" || return 1
    printf '%s|%s|%s|%s|%s\n' \
        "$PARSED_INSTANCE" "$PARSED_PORT" "$PARSED_PROTO" \
        "$PARSED_NETWORK" "$PARSED_SOURCE"
}

managed_rule_lines() {
    if lifecycle_available; then
        ufw_docker_managed_status_lines
    else
        require_command ufw || return 1
        LC_ALL=C ufw status numbered 2>/dev/null |
            grep -F 'ALLOW FWD' |
            grep -F '# allow ' || true
    fi
}

managed_rule_comments() {
    managed_rule_lines | sed -n 's/.*# allow /allow /p'
}

trigger_agent_recreation() {
    command -v docker >/dev/null 2>&1 || return 0
    local -a agents=()
    mapfile -t agents < <(docker ps --filter 'name=ufw-docker-agent' -q 2>/dev/null || true)
    (( ${#agents[@]} > 0 )) || return 0

    info "触发 ufw-docker-agent 重建..."
    if [[ "$DRY_RUN" == "1" ]]; then
        print_cmd docker rm -f "${agents[@]}"
    else
        docker rm -f "${agents[@]}" >/dev/null ||
            warn "ufw-docker-agent 重建触发失败。"
    fi
}

# Override rules.sh so both the menu and rulectl use the shared lifecycle
# implementation. A failed recreation is reported; existing rules are never
# automatically removed.
enhanced_reload_rules() {
    lifecycle_available || {
        error "规则生命周期库不可用，无法执行增强重载。"
        return 1
    }
    require_core || return 1

    local count
    count="$(managed_rule_lines | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    if (( count == 0 )); then
        info "当前没有需要重载的 UFW-Docker 规则。"
        return 0
    fi

    ssh_context_warning
    warn "增强重载会统一处理普通规则和 from:来源 IP 规则。"
    warn "重载失败时不会自动删除旧规则。"
    confirm "确认重载 $count 条 UFW 规则记录？" || {
        info "已取消。"
        return 0
    }

    if ufw_docker_reload_rules "$CORE_BIN" "$DRY_RUN"; then
        trigger_agent_recreation
        success "规则重载完成。"
        return 0
    fi

    error "部分规则未能重载，请根据上方失败项人工复核。"
    return 1
}

canonical_path() {
    local path="${1:-}"
    if command -v realpath >/dev/null 2>&1; then
        realpath -m "$path" 2>/dev/null || printf '%s\n' "$path"
    elif command -v readlink >/dev/null 2>&1; then
        readlink -f "$path" 2>/dev/null || printf '%s\n' "$path"
    else
        printf '%s\n' "$path"
    fi
}

install_if_different() {
    local mode="${1:?missing mode}"
    local source="${2:?missing source}"
    local destination="${3:?missing destination}"
    [[ -r "$source" ]] || return 0
    if [[ "$(canonical_path "$source")" == "$(canonical_path "$destination")" ]]; then
        return 0
    fi
    install -m "$mode" "$source" "$destination"
}

install_menu_command() {
    require_root "$@" || return 1
    local source_modules="$MENU_MODULE_DIR"
    mkdir -p "$INSTALL_MODULE_DIR" "$INSTALL_DOC_DIR" "$INSTALL_HELPER_DIR"

    install_if_different 0755 "$SCRIPT_PATH" "$INSTALL_BIN"
    local module
    for module in common validation ui docker rules system app extras; do
        install_if_different 0644 "$source_modules/$module.sh" "$INSTALL_MODULE_DIR/$module.sh"
    done
    ln -sfn "$INSTALL_BIN" "$INSTALL_ALIAS"

    install_if_different 0644 "$SCRIPT_DIR/MENU.md" "$INSTALL_DOC_DIR/MENU.md"
    install_if_different 0644 "$SCRIPT_DIR/RULE_LIFECYCLE.md" "$INSTALL_DOC_DIR/RULE_LIFECYCLE.md"
    install_if_different 0644 "$SCRIPT_DIR/VERSION" "$INSTALL_DOC_DIR/VERSION"

    local helper
    for helper in print-iptables.sh print-ip6tables.sh trace-iptables.sh trace-ip6tables.sh; do
        install_if_different 0755 "$SCRIPT_DIR/$helper" "$INSTALL_HELPER_DIR/$helper"
    done

    install_if_different 0644 "$SCRIPT_DIR/lib/ufw-docker-rules.sh" "$RULECTL_LIB"
    install_if_different 0755 "$SCRIPT_DIR/ufw-docker-rulectl" "$RULECTL_BIN"

    success "菜单已安装：$INSTALL_BIN"
    success "快捷命令：$INSTALL_ALIAS"
    if [[ -x "$RULECTL_BIN" ]]; then
        success "规则生命周期工具：$RULECTL_BIN"
    fi
}

uninstall_menu_command() {
    require_root "$@" || return 1
    rm -f "$INSTALL_ALIAS" "$INSTALL_BIN" "$RULECTL_BIN"
    rm -rf "$INSTALL_MODULE_DIR" "$INSTALL_DOC_DIR" "$INSTALL_HELPER_DIR"
    success "菜单和规则生命周期组件已卸载。"
}

resolve_rulectl() {
    local candidate
    for candidate in \
        "$SCRIPT_DIR/ufw-docker-rulectl" \
        "$(command -v ufw-docker-rulectl 2>/dev/null || true)" \
        "$RULECTL_BIN"; do
        [[ -n "$candidate" && -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}

core_raw_command_prompt() {
    require_core || return 1
    local input
    local -a args=()
    printf '请输入传给 ufw 的参数（例如 status verbose）：'
    read -r input || return 1
    [[ -n "$input" ]] || return 1
    read -r -a args <<< "$input"
    warn "该入口等价于 ufw-docker raw-command；不解释管道、重定向或命令替换。"
    run_mutating_cmd "$CORE_BIN" raw-command "${args[@]}"
}

core_add_service_rule_prompt() {
    require_core || return 1
    local service port_proto
    warn "add-service-rule 是 ufw-docker-agent 使用的内部高级命令。"
    warn "普通 Swarm 用户应优先使用主菜单 9 的 service allow。"
    printf '请输入 Swarm service ID/名称：'
    read -r service || return 1
    [[ -n "$service" ]] || { error "Service 不能为空。"; return 1; }
    printf '请输入 TargetPort/协议（例如 80/tcp）：'
    read -r port_proto || return 1
    validate_port_proto "$port_proto" || {
        error "端口格式无效：$port_proto"
        return 1
    }
    run_mutating_cmd "$CORE_BIN" add-service-rule "$service" "$port_proto"
}

rulectl_view_prompt() {
    local tool
    tool="$(resolve_rulectl)" || {
        error "未找到 ufw-docker-rulectl。请从仓库重新安装菜单。"
        return 1
    }
    "$tool" list --format tsv || true
}

rulectl_reload_preview() {
    local tool
    tool="$(resolve_rulectl)" || {
        error "未找到 ufw-docker-rulectl。请从仓库重新安装菜单。"
        return 1
    }
    "$tool" reload --dry-run || true
}

advanced_core_menu() {
    local choice
    while true; do
        clear_screen
        render_banner
        separator
        say "  1. 查看 ufw-docker 原始 help"
        say "  2. 查看 ufw-docker man page"
        say "  3. raw-command 高级 UFW 命令"
        say "  4. add-service-rule 内部高级命令"
        say "  5. rulectl TSV 规则清单"
        say "  6. rulectl 重载命令预览"
        say "  0. 返回"
        separator
        printf '选择：'
        read -r choice || choice=0
        case "$choice" in
            1)
                require_core && "$CORE_BIN" help 2>&1 || true
                pause_screen
                ;;
            2)
                require_core && "$CORE_BIN" man 2>&1 || true
                pause_screen
                ;;
            3) core_raw_command_prompt; pause_screen ;;
            4) core_add_service_rule_prompt; pause_screen ;;
            5) rulectl_view_prompt; pause_screen ;;
            6) rulectl_reload_preview; pause_screen ;;
            0) return ;;
            *) warn "无效选择。"; pause_screen ;;
        esac
    done
}

# Override system.sh diagnostics to expose every remaining upstream/fork CLI
# entry point that is not already represented by the primary menu.
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
        say " 13. ufw-docker 原生命令 / 内部命令 ▶"
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
            13) advanced_core_menu ;;
            0) return ;;
            *) warn "无效选择。"; pause_screen ;;
        esac
    done
}
