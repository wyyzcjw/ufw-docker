#!/usr/bin/env bash
# shellcheck shell=bash
# Self-contained menu installer. Loaded after extras.sh to override its installer.

SYSTEM_CORE_BIN="/usr/local/bin/ufw-docker"

install_local_core_if_missing() {
    local local_core="$SCRIPT_DIR/ufw-docker"
    command -v install >/dev/null 2>&1 || {
        error "缺少 install 命令，无法安装系统文件。"
        return 1
    }
    mkdir -p "$(dirname "$SYSTEM_CORE_BIN")"
    if [[ -x "$SYSTEM_CORE_BIN" ]]; then
        return 0
    fi
    if [[ -x "$local_core" ]]; then
        install -m 0755 "$local_core" "$SYSTEM_CORE_BIN"
        success "核心命令已安装：$SYSTEM_CORE_BIN"
        return 0
    fi
    warn "没有找到仓库内的 ufw-docker 核心脚本；菜单已安装，但后续需要单独安装核心命令。"
}

install_menu_command() {
    require_root "$@" || return 1
    local source_modules="$MENU_MODULE_DIR"
    command -v install >/dev/null 2>&1 || {
        error "缺少 install 命令。"
        return 1
    }
    mkdir -p "$(dirname "$INSTALL_BIN")" "$INSTALL_MODULE_DIR" "$INSTALL_DOC_DIR" "$INSTALL_HELPER_DIR"

    # A temporary one-click checkout disappears when the menu exits. Make the
    # persistent menu usable afterwards by copying the local core only when the
    # system does not already have one. Existing system cores are never silently
    # overwritten by menu option 99; the bootstrap --install mode handles updates.
    install_local_core_if_missing || return 1

    install_if_different 0755 "$SCRIPT_PATH" "$INSTALL_BIN"
    local module
    for module in common validation ui docker rules system app extras ruleview installer; do
        install_if_different 0644 "$source_modules/$module.sh" "$INSTALL_MODULE_DIR/$module.sh"
    done
    ln -sfn "$INSTALL_BIN" "$INSTALL_ALIAS"

    install_if_different 0644 "$SCRIPT_DIR/MENU.md" "$INSTALL_DOC_DIR/MENU.md"
    install_if_different 0644 "$SCRIPT_DIR/RULE_LIFECYCLE.md" "$INSTALL_DOC_DIR/RULE_LIFECYCLE.md"
    install_if_different 0644 "$SCRIPT_DIR/RULE_VIEW.md" "$INSTALL_DOC_DIR/RULE_VIEW.md"
    install_if_different 0644 "$SCRIPT_DIR/COMMAND_COVERAGE.md" "$INSTALL_DOC_DIR/COMMAND_COVERAGE.md"
    install_if_different 0644 "$SCRIPT_DIR/ONE_CLICK_INSTALL.md" "$INSTALL_DOC_DIR/ONE_CLICK_INSTALL.md"
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
    info "核心命令 $SYSTEM_CORE_BIN 未自动删除；如需完整卸载，请使用菜单 90 或 ufw-docker uninstall。"
}
