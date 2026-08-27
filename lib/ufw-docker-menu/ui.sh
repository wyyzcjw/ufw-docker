#!/usr/bin/env bash
# shellcheck shell=bash
# Generated module for ufw-docker-menu.

render_banner() {
    local os_name ufw_status docker_status backend svc cols
    os_name="$(os_pretty_name)"
    ufw_status="$(ufw_state)"
    docker_status="$(docker_state)"
    backend="$(iptables_backend)"
    svc="$(service_state)"
    cols="$(terminal_cols)"

    if (( cols >= 92 )); then
        printf '%s' "$C_BLUE"
        cat <<'BANNER'
 ██╗   ██╗███████╗██╗    ██╗      ██████╗  ██████╗  ██████╗██╗  ██╗███████╗██████╗
 ██║   ██║██╔════╝██║    ██║      ██╔══██╗██╔═══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗
 ██║   ██║█████╗  ██║ █╗ ██║█████╗██║  ██║██║   ██║██║     █████╔╝ █████╗  ██████╔╝
 ██║   ██║██╔══╝  ██║███╗██║╚════╝██║  ██║██║   ██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗
 ╚██████╔╝██║     ╚███╔███╔╝      ██████╔╝╚██████╔╝╚██████╗██║  ██╗███████╗██║  ██║
  ╚═════╝ ╚═╝      ╚══╝╚══╝       ╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝
BANNER
        printf '%s\n' "$C_RESET"
        printf '                 %sUFW-DOCKER 一键管理工具  %s%s%s\n' \
            "$C_ORANGE" "$C_BOLD" "$MENU_VERSION" "$C_RESET"
    else
        printf '%s%s=== UFW-DOCKER 一键管理工具 %s ===%s\n' \
            "$C_BLUE" "$C_BOLD" "$MENU_VERSION" "$C_RESET"
    fi

    printf '项目地址：%s\n' "$PROJECT_URL"
    printf '%s系统：%s%s  %sUFW：%s%s  %sDocker：%s%s\n' \
        "$C_CYAN" "$os_name" "$C_RESET" \
        "$C_CYAN" "$ufw_status" "$C_RESET" \
        "$C_CYAN" "$docker_status" "$C_RESET"
    printf '%s后端：%s%s  %s自动重载服务：%s%s\n' \
        "$C_CYAN" "$backend" "$C_RESET" \
        "$C_CYAN" "$svc" "$C_RESET"
}

menu_row() {
    local left="$1"
    local right="${2:-}"
    local cols
    cols="$(terminal_cols)"
    if (( cols >= 96 )) && [[ -n "$right" ]] && [[ -t 1 ]]; then
        printf '  %b' "$left"
        printf '\033[52G%b\n' "$right"
    else
        printf '  %b\n' "$left"
        [[ -n "$right" ]] && printf '  %b\n' "$right"
    fi
}

render_main_menu() {
    render_banner
    separator
    menu_row "${C_GREEN}1. 状态与规则总览${C_RESET}" \
             "${C_GREEN}7. 安装与规则检查  ▶${C_RESET}"
    menu_row "${C_GREEN}2. 容器端口放行  ▶${C_RESET}" \
             "${C_GREEN}8. 自动重载服务管理  ▶${C_RESET}"
    menu_row "${C_GREEN}3. 指定来源 IP 放行  ▶${C_RESET}" \
             "${C_GREEN}9. Docker Swarm 管理  ▶${C_RESET}"
    menu_row "${C_GREEN}4. 查询与删除规则  ▶${C_RESET}" \
             "${C_GREEN}10. Docker 子网配置  ▶${C_RESET}"
    menu_row "${C_GREEN}5. 重载与修复规则  ▶${C_RESET}" \
             "${C_GREEN}11. 诊断与调试工具  ▶${C_RESET}"
    menu_row "${C_GREEN}6. 容器/端口/网络信息  ▶${C_RESET}" \
             "${C_GREEN}12. 帮助与项目说明${C_RESET}"
    separator
    menu_row "${C_BLUE}00. 检查菜单更新${C_RESET}" \
             "${C_MAGENTA}90. 卸载 UFW-Docker${C_RESET}"
    menu_row "${C_GRAY}99. 安装菜单快捷命令${C_RESET}" \
             "${C_RED}88. 退出${C_RESET}"
    separator
}

read_main_choice() {
    local choice
    printf '%s请输入你的选择：%s' "$C_RED" "$C_RESET" >&2
    read -r choice || choice=88
    printf '%s\n' "$choice"
}

show_dashboard() {
    clear_screen
    render_banner
    separator
    printf '%s环境检查%s\n\n' "$C_BOLD" "$C_RESET"
    printf '  %-20s %s\n' "内核" "$(uname -srmo 2>/dev/null || uname -a)"
    printf '  %-20s %s\n' "Bash" "$BASH_VERSION"
    printf '  %-20s %s\n' "UFW" "$(ufw_state)"
    printf '  %-20s %s\n' "Docker" "$(docker_state)"
    printf '  %-20s %s\n' "iptables" "$(iptables_backend)"
    printf '  %-20s %s\n' "IPv6 工具" "$(command -v ip6tables >/dev/null 2>&1 && printf '可用' || printf '不可用')"
    printf '  %-20s %s\n' "自动重载服务" "$(service_state)"
    if resolve_core >/dev/null; then
        printf '  %-20s %s\n' "核心命令" "$CORE_BIN"
    else
        printf '  %-20s %s\n' "核心命令" "未找到"
    fi
    printf '  %-20s %s\n' "菜单脚本" "$SCRIPT_PATH"

    if resolve_core >/dev/null; then
        printf '\n%s核心 ufw-docker status%s\n' "$C_BOLD" "$C_RESET"
        separator 80
        "$CORE_BIN" status 2>&1 || warn "核心 status 执行失败。"
    fi

    printf '\n%sUFW-Docker 已管理规则%s\n' "$C_BOLD" "$C_RESET"
    separator 80
    local rules=""
    rules="$(managed_rule_lines 2>/dev/null || true)"
    [[ -n "$rules" ]] && printf '%s\n' "$rules" || say "当前没有可显示的 UFW-Docker 规则。"
    pause_screen
}
