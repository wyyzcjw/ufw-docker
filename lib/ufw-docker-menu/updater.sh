#!/usr/bin/env bash
# shellcheck shell=bash
# Root self-update center for ufw-docker-menu.

OFFICIAL_UPDATE_BOOTSTRAP_URL="https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh"

update_downloader() {
    if command -v curl >/dev/null 2>&1; then
        printf 'curl\n'
    elif command -v wget >/dev/null 2>&1; then
        printf 'wget\n'
    else
        return 1
    fi
}

update_download_stdout() {
    local url="${1:?missing url}"
    local downloader
    downloader="$(update_downloader)" || {
        error "检查更新需要 curl 或 wget。"
        return 1
    }
    case "$downloader" in
        curl) curl -fsSL --retry 3 --connect-timeout 10 "$url" ;;
        wget) wget -qO- --timeout=10 --tries=3 "$url" ;;
        *) return 1 ;;
    esac
}

update_download_file() {
    local url="${1:?missing url}"
    local destination="${2:?missing destination}"
    local downloader
    downloader="$(update_downloader)" || {
        error "下载安装需要 curl 或 wget。"
        return 1
    }
    case "$downloader" in
        curl) curl -fL --retry 3 --connect-timeout 10 --progress-bar -o "$destination" "$url" ;;
        wget) wget --timeout=10 --tries=3 -O "$destination" "$url" ;;
        *) return 1 ;;
    esac
}

update_remote_version() {
    local version
    version="$(update_download_stdout "$UPDATE_VERSION_URL" 2>/dev/null || true)"
    version="$(printf '%s' "$version" | tr -d '\r\n[:space:]')"
    [[ "$version" =~ ^v?[0-9]+([.][0-9]+){1,3}([+-][A-Za-z0-9._-]+)?$ ]] || return 1
    printf '%s\n' "$version"
}

version_numeric_parts() {
    local version="${1#v}"
    local major=0 minor=0 patch=0 build=0
    version="${version%%[-+]*}"
    IFS='.' read -r major minor patch build <<< "$version"
    major="${major:-0}"
    minor="${minor:-0}"
    patch="${patch:-0}"
    build="${build:-0}"
    [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$patch" =~ ^[0-9]+$ && "$build" =~ ^[0-9]+$ ]] || return 1
    printf '%s %s %s %s\n' "$major" "$minor" "$patch" "$build"
}

version_is_newer() {
    local remote="${1:-}" local_version="${2:-}"
    local -a r=() l=()
    local i
    read -r -a r <<< "$(version_numeric_parts "$remote")" || return 1
    read -r -a l <<< "$(version_numeric_parts "$local_version")" || return 1
    for i in 0 1 2 3; do
        if (( 10#${r[$i]} > 10#${l[$i]} )); then
            return 0
        elif (( 10#${r[$i]} < 10#${l[$i]} )); then
            return 1
        fi
    done
    return 1
}

show_update_status() {
    local remote=""
    printf '%s更新状态%s\n' "$C_BOLD" "$C_RESET"
    printf '  当前菜单版本: %s%s%s\n' "$C_CYAN" "$MENU_VERSION" "$C_RESET"
    printf '  检查地址:     %s\n' "$UPDATE_VERSION_URL"
    if remote="$(update_remote_version)"; then
        printf '  master VERSION: %s%s%s\n' "$C_CYAN" "$remote" "$C_RESET"
        if version_is_newer "$remote" "$MENU_VERSION"; then
            printf '  状态: %s发现新版本%s\n' "$C_YELLOW" "$C_RESET"
        elif [[ "${remote#v}" == "${MENU_VERSION#v}" ]]; then
            printf '  状态: %s已是当前版本%s\n' "$C_GREEN" "$C_RESET"
        else
            printf '  状态: %s远程版本不高于当前版本%s\n' "$C_GRAY" "$C_RESET"
        fi
    else
        printf '  master VERSION: %s检查失败%s\n' "$C_RED" "$C_RESET"
        warn "无法读取远程 VERSION；仍可手动选择 Root 更新。"
    fi
}

show_update_security_note() {
    printf '\n%sRoot 直接更新说明%s\n' "$C_BOLD" "$C_RESET"
    say "  - 只从本项目 GitHub 官方 raw 地址下载 install.sh。"
    say "  - 下载后先执行 bash -n 和 bootstrap --self-test，再允许执行。"
    say "  - 更新会覆盖 /usr/local 下已安装的程序文件。"
    say "  - 更新程序文件不会自动执行 ufw enable、不会修改现有 UFW 规则。"
    say "  - 稳定版优先使用 GitHub Release；当前无 Release 时会由 bootstrap 回退 master。"
}

root_update_build_args() {
    local channel="${1:-stable}"
    printf '%s\n' '--install' '--no-run'
    [[ "$channel" == "dev" ]] && printf '%s\n' '--dev'
}

root_update_from_github() {
    local channel="${1:-stable}"
    local tmp_dir bootstrap new_version=""
    local -a bootstrap_args=()

    [[ "$channel" == "stable" || "$channel" == "dev" ]] || {
        error "未知更新通道：$channel"
        return 2
    }
    if [[ "$TESTING" != "1" && "${EUID:-$(id -u)}" -ne 0 ]]; then
        error "Root 直接更新需要 root 权限。请使用 sudo ufd 或 root 运行菜单。"
        return 1
    fi
    update_downloader >/dev/null || {
        error "缺少 curl/wget，无法下载安装。"
        return 1
    }
    command -v mktemp >/dev/null 2>&1 || {
        error "缺少 mktemp，无法创建安全临时目录。"
        return 1
    }

    mapfile -t bootstrap_args < <(root_update_build_args "$channel")

    printf '\n%s准备 Root 直接更新%s\n' "$C_BOLD" "$C_RESET"
    printf '  通道: %s\n' "$channel"
    printf '  Bootstrap: %s\n' "$OFFICIAL_UPDATE_BOOTSTRAP_URL"
    printf '  将执行: bash install.sh'
    printf ' %s' "${bootstrap_args[@]}"
    printf '\n'
    warn "该操作会以 root 权限执行从 GitHub 下载并校验后的官方安装脚本。"
    confirm "确认下载并更新已安装的 UFW-Docker 程序文件？" || {
        info "已取消更新。"
        return 0
    }

    umask 077
    tmp_dir="$(mktemp -d -t ufw-docker-update.XXXXXXXX)" || {
        error "创建临时目录失败。"
        return 1
    }
    bootstrap="$tmp_dir/install.sh"

    info "正在下载最新官方 install.sh ..."
    if ! update_download_file "$OFFICIAL_UPDATE_BOOTSTRAP_URL" "$bootstrap"; then
        rm -rf -- "$tmp_dir"
        error "下载 install.sh 失败。"
        return 1
    fi

    if ! grep -Fq 'REPO="wyyzcjw/ufw-docker"' "$bootstrap"; then
        rm -rf -- "$tmp_dir"
        error "下载脚本未通过仓库身份检查，已拒绝执行。"
        return 1
    fi
    if ! bash -n "$bootstrap"; then
        rm -rf -- "$tmp_dir"
        error "下载脚本 Bash 语法检查失败，已拒绝执行。"
        return 1
    fi
    if ! NO_COLOR=1 bash "$bootstrap" --self-test >/dev/null; then
        rm -rf -- "$tmp_dir"
        error "下载脚本自检失败，已拒绝执行。"
        return 1
    fi
    success "Bootstrap 校验通过。"

    if [[ "$DRY_RUN" == "1" ]]; then
        print_cmd bash "$bootstrap" "${bootstrap_args[@]}"
        info "DRY-RUN：未执行安装。"
        rm -rf -- "$tmp_dir"
        return 0
    fi

    if ! bash "$bootstrap" "${bootstrap_args[@]}"; then
        rm -rf -- "$tmp_dir"
        error "更新失败；当前菜单进程仍在运行，请检查上方输出。"
        return 1
    fi
    rm -rf -- "$tmp_dir"

    if [[ -x "$INSTALL_BIN" ]]; then
        new_version="$(NO_COLOR=1 "$INSTALL_BIN" --version 2>/dev/null || true)"
    fi
    if [[ -n "$new_version" ]]; then
        success "程序文件更新完成，已安装版本：$new_version"
    else
        success "程序文件更新完成。"
    fi
    warn "当前正在运行的仍是更新前菜单进程。请退出后重新执行 sudo ufd 载入新版本。"
}

show_manual_update_commands() {
    cat <<'EOF'
稳定通道：
  bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --install --no-run

强制 master：
  bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --install --dev --no-run

更新完成后：
  sudo ufd
EOF
}

check_updates() {
    local choice
    while true; do
        clear_screen
        render_banner
        separator
        show_update_status
        show_update_security_note
        printf '\n'
        separator
        say "  1. 重新检查远程版本"
        say "  2. Root 直接下载安装稳定版（推荐）"
        say "  3. Root 直接下载安装 master 开发版"
        say "  4. 查看手动更新命令"
        say "  0. 返回主菜单"
        separator
        printf '选择：'
        read -r choice || choice=0
        case "$choice" in
            1) continue ;;
            2) root_update_from_github stable; pause_screen ;;
            3) root_update_from_github dev; pause_screen ;;
            4) clear_screen; show_manual_update_commands; pause_screen ;;
            0) return ;;
            *) warn "无效选择。"; pause_screen ;;
        esac
    done
}
