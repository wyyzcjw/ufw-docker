#!/usr/bin/env bash
# shellcheck shell=bash
# Installation overrides for optional lifecycle tooling.

RULECTL_BIN="/usr/local/bin/ufw-docker-rulectl"
RULECTL_LIB="/usr/local/lib/ufw-docker/ufw-docker-rules.sh"

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
