#!/usr/bin/env bash
# shellcheck shell=bash
# Lifecycle integration and installation overrides for ufw-docker-menu.

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
        ufw status numbered 2>/dev/null | grep -F '# allow ' || true
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

install_menu_command() {
    require_root "$@" || return 1
    local source_modules="$MENU_MODULE_DIR"
    mkdir -p "$INSTALL_MODULE_DIR" "$INSTALL_DOC_DIR" "$INSTALL_HELPER_DIR"

    install -m 0755 "$SCRIPT_PATH" "$INSTALL_BIN"
    local module
    for module in common validation ui docker rules system app extras; do
        install -m 0644 "$source_modules/$module.sh" "$INSTALL_MODULE_DIR/$module.sh"
    done
    ln -sfn "$INSTALL_BIN" "$INSTALL_ALIAS"

    [[ -r "$SCRIPT_DIR/MENU.md" ]] && install -m 0644 "$SCRIPT_DIR/MENU.md" "$INSTALL_DOC_DIR/MENU.md"
    [[ -r "$SCRIPT_DIR/RULE_LIFECYCLE.md" ]] && install -m 0644 "$SCRIPT_DIR/RULE_LIFECYCLE.md" "$INSTALL_DOC_DIR/RULE_LIFECYCLE.md"
    [[ -r "$SCRIPT_DIR/VERSION" ]] && install -m 0644 "$SCRIPT_DIR/VERSION" "$INSTALL_DOC_DIR/VERSION"

    local helper
    for helper in print-iptables.sh print-ip6tables.sh trace-iptables.sh trace-ip6tables.sh; do
        if [[ -r "$SCRIPT_DIR/$helper" ]]; then
            install -m 0755 "$SCRIPT_DIR/$helper" "$INSTALL_HELPER_DIR/$helper"
        fi
    done

    if [[ -r "$SCRIPT_DIR/lib/ufw-docker-rules.sh" ]]; then
        install -m 0644 "$SCRIPT_DIR/lib/ufw-docker-rules.sh" "$RULECTL_LIB"
    fi
    if [[ -r "$SCRIPT_DIR/ufw-docker-rulectl" ]]; then
        install -m 0755 "$SCRIPT_DIR/ufw-docker-rulectl" "$RULECTL_BIN"
    fi

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
