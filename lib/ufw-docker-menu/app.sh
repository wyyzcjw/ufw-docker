#!/usr/bin/env bash
# shellcheck shell=bash
# Application entrypoint and self-tests for ufw-docker-menu.

show_menu_help() {
    cat <<EOF
UFW-Docker 交互管理菜单 $MENU_VERSION

一键运行：
  bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh)

永久安装：
  bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --install

菜单内更新：
  主菜单 00 -> Root 直接下载安装稳定版或 master 开发版

用法：
  ufw-docker-menu
  ufw-docker-menu --help
  ufw-docker-menu --version
  ufw-docker-menu --print-main-menu
  ufw-docker-menu --self-test
  sudo ufw-docker-menu --install-menu
  sudo ufw-docker-menu --uninstall-menu

规则生命周期工具：
  ufw-docker-rulectl list --format tsv
  ufw-docker-rulectl delete --container NAME --source CIDR
  ufw-docker-rulectl reload --dry-run

规则视图：
  < 80 列     手机卡片视图
  80-109 列   紧凑表格
  >= 110 列   完整表格
  菜单会检测容器当前 IP，并标记 IP 已变化、容器不存在或已停止的规则。

环境变量：
  UFW_DOCKER_BIN                      指定 ufw-docker 核心脚本
  UFW_DOCKER_MENU_DRY_RUN=1           仅打印命令，不执行修改
  UFW_DOCKER_MENU_NO_AUTO_SUDO=1      禁止自动 sudo 重启
  UFW_DOCKER_MENU_LOCK_FILE           自定义实例锁文件
  UFW_DOCKER_MENU_UPDATE_URL          自定义只读版本检查地址
  UFW_DOCKER_MENU_RULE_VIEW           auto|card|compact|full
  UFW_DOCKER_MENU_RULE_HEALTH_CHECK=0 禁用 Docker 规则健康检查
  UFW_DOCKER_MENU_TESTING=1           测试模式
  NO_COLOR=1                          禁用 ANSI 颜色

项目：$PROJECT_URL
EOF
}

self_test_assert() {
    local description="$1"
    shift
    if "$@"; then
        printf 'ok - %s\n' "$description"
    else
        printf 'not ok - %s\n' "$description" >&2
        return 1
    fi
}

self_test() {
    local failed=0
    require_bash_version || return 1

    self_test_assert "valid TCP port" validate_port_proto "443/tcp" || failed=1
    if validate_port_proto "70000/tcp"; then
        printf 'not ok - invalid high port rejected\n' >&2
        failed=1
    else
        printf 'ok - invalid high port rejected\n'
    fi

    self_test_assert "valid IPv4 CIDR" validate_ip_or_cidr "192.0.2.0/24" || failed=1
    self_test_assert "valid IPv6 CIDR" validate_ip_or_cidr "2001:db8::/64" || failed=1
    if validate_ip_or_cidr "999.1.2.3/24"; then
        printf 'not ok - invalid IPv4 rejected\n' >&2
        failed=1
    else
        printf 'ok - invalid IPv4 rejected\n'
    fi

    if parse_rule_comment "allow nginx/v6 80/tcp frontend from:2001:db8::/64" &&
       [[ "$PARSED_INSTANCE" == "nginx" ]] &&
       [[ "$PARSED_PORT" == "80" ]] &&
       [[ "$PARSED_PROTO" == "tcp" ]] &&
       [[ "$PARSED_NETWORK" == "frontend" ]] &&
       [[ "$PARSED_SOURCE" == "2001:db8::/64" ]] &&
       [[ "$PARSED_IS_V6" == "1" ]]; then
        printf 'ok - source restricted rule parser\n'
    else
        printf 'not ok - source restricted rule parser\n' >&2
        failed=1
    fi

    if rule_parse_line "[ 7] 172.19.0.2 80/tcp ALLOW FWD 192.0.2.10 # allow nginx 80/tcp frontend from:192.0.2.10" &&
       [[ "$RULEVIEW_NUMBER" == "7" ]] &&
       [[ "$RULEVIEW_CONTAINER" == "nginx" ]] &&
       [[ "$RULEVIEW_PORT_PROTO" == "80/tcp" ]] &&
       [[ "$RULEVIEW_SOURCE" == "192.0.2.10" ]] &&
       [[ "$RULEVIEW_TARGET" == "172.19.0.2" ]]; then
        printf 'ok - responsive rule record parser\n'
    else
        printf 'not ok - responsive rule record parser\n' >&2
        failed=1
    fi

    local module
    for module in common validation ui docker rules system app extras ruleview installer updater; do
        if [[ -r "$MENU_MODULE_DIR/$module.sh" ]]; then
            printf 'ok - module %s\n' "$module"
        else
            printf 'not ok - module %s missing\n' "$module" >&2
            failed=1
        fi
    done

    if [[ -r "$SCRIPT_DIR/lib/ufw-docker-rules.sh" || -r /usr/local/lib/ufw-docker/ufw-docker-rules.sh ]]; then
        printf 'ok - lifecycle rule library\n'
    else
        printf 'not ok - lifecycle rule library missing\n' >&2
        failed=1
    fi

    declare -F show_grouped_rules >/dev/null 2>&1 || {
        printf 'not ok - grouped rule view\n' >&2
        failed=1
    }
    declare -F collect_rule_stats >/dev/null 2>&1 || {
        printf 'not ok - rule stats collector\n' >&2
        failed=1
    }
    declare -F check_updates >/dev/null 2>&1 || {
        printf 'not ok - update center\n' >&2
        failed=1
    }
    declare -F root_update_from_github >/dev/null 2>&1 || {
        printf 'not ok - root updater\n' >&2
        failed=1
    }
    self_test_assert "semantic version newer" version_is_newer "1.5.0" "1.4.0" || failed=1
    if version_is_newer "1.4.0" "1.5.0"; then
        printf 'not ok - semantic version downgrade rejected\n' >&2
        failed=1
    else
        printf 'ok - semantic version downgrade rejected\n'
    fi

    if [[ -x "$SCRIPT_PATH" || "$TESTING" == "1" ]]; then
        printf 'ok - menu entrypoint available\n'
    else
        warn "入口脚本当前没有 executable bit；仓库安装前请执行 chmod +x ufw-docker-menu。"
    fi

    (( failed == 0 ))
}

interactive_main() {
    require_linux || return 1
    require_bash_version || return 1
    require_root "$@" || return 1
    acquire_session_lock || return 1

    require_command ufw || return 1
    require_command docker || return 1
    if ! resolve_core >/dev/null; then
        warn "尚未找到 ufw-docker 核心命令；部分菜单不可用。"
    fi

    local choice
    while true; do
        clear_screen
        render_main_menu
        choice="$(read_main_choice)"
        case "$choice" in
            1) show_dashboard ;;
            2) apply_container_rule allow ;;
            3) apply_container_rule allow-ip ;;
            4) rules_menu ;;
            5) reload_menu ;;
            6) container_info_menu ;;
            7) install_check_menu ;;
            8) service_menu ;;
            9) swarm_menu ;;
            10) subnet_menu ;;
            11) diagnostic_menu ;;
            12) show_help_page ;;
            00|0) check_updates ;;
            90) uninstall_core_menu ;;
            99) install_menu_command --install-menu; pause_screen ;;
            88|q|Q) clear_screen; return 0 ;;
            *) warn "无效选择：$choice"; pause_screen ;;
        esac
    done
}

main() {
    local action="${1:-}"
    case "$action" in
        --help|-h|help)
            show_menu_help
            ;;
        --version|-V|version)
            printf '%s\n' "$MENU_VERSION"
            ;;
        --print-main-menu)
            render_main_menu
            ;;
        --self-test)
            self_test
            ;;
        --install-menu)
            require_linux && require_bash_version && install_menu_command --install-menu
            ;;
        --uninstall-menu)
            require_linux && require_bash_version && uninstall_menu_command --uninstall-menu
            ;;
        "")
            interactive_main "$@"
            ;;
        *)
            error "未知参数：$action"
            show_menu_help
            return 2
            ;;
    esac
}
