#!/usr/bin/env bash
# shellcheck shell=bash
# Generated module for ufw-docker-menu.

say() {
    printf '%s\n' "$*"
}

info() {
    printf '%s[信息]%s %s\n' "$C_BLUE" "$C_RESET" "$*"
}

success() {
    printf '%s[成功]%s %s\n' "$C_GREEN" "$C_RESET" "$*"
}

warn() {
    printf '%s[警告]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2
}

error() {
    printf '%s[错误]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
}

die() {
    error "$*"
    return 1
}

clear_screen() {
    if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
        printf '\033[2J\033[H'
    else
        printf '\n'
    fi
}

pause_screen() {
    [[ "$TESTING" == "1" ]] && return 0
    printf '\n%s按 Enter 返回菜单...%s' "$C_GRAY" "$C_RESET"
    read -r _ || true
}

terminal_cols() {
    local cols="${COLUMNS:-}"
    if [[ -z "$cols" ]] && command -v tput >/dev/null 2>&1; then
        cols="$(tput cols 2>/dev/null || true)"
    fi
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=100
    printf '%s\n' "$cols"
}

separator() {
    local width="${1:-$(terminal_cols)}"
    (( width > 110 )) && width=110
    (( width < 60 )) && width=60
    printf '%s' "$C_GREEN"
    printf '%*s' "$width" '' | tr ' ' '-'
    printf '%s\n' "$C_RESET"
}

print_cmd() {
    local arg
    printf '%s' "$C_CYAN"
    for arg in "$@"; do
        printf '%q ' "$arg"
    done
    printf '%s\n' "$C_RESET"
}

run_cmd() {
    print_cmd "$@"
    if [[ "$DRY_RUN" == "1" ]]; then
        info "DRY-RUN：未实际执行。"
        return 0
    fi
    "$@"
}

confirm() {
    local prompt="${1:-确认执行？}"
    local answer
    [[ "$TESTING" == "1" ]] && return 0
    printf '%s%s [y/N]: %s' "$C_YELLOW" "$prompt" "$C_RESET"
    read -r answer || return 1
    [[ "$answer" =~ ^([yY]|[yY][eE][sS])$ ]]
}

require_linux() {
    [[ "$(uname -s 2>/dev/null || true)" == "Linux" ]] || {
        die "本工具仅支持 Linux。"
        return 1
    }
}

require_bash_version() {
    if (( BASH_VERSINFO[0] < 4 )) ||
       (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3 )); then
        die "Bash 版本必须 >= 4.3，当前为 ${BASH_VERSION}。"
        return 1
    fi
}

require_root() {
    [[ "$TESTING" == "1" ]] && return 0
    if (( EUID == 0 )); then
        return 0
    fi
    if [[ "$NO_AUTO_SUDO" != "1" ]] && command -v sudo >/dev/null 2>&1; then
        info "需要 root 权限，正在通过 sudo 重新启动..."
        exec sudo -E "$SCRIPT_PATH" "$@"
    fi
    die "请使用 root 用户或 sudo 运行本工具。"
}

acquire_session_lock() {
    [[ "$TESTING" == "1" ]] && return 0
    if ! command -v flock >/dev/null 2>&1; then
        warn "系统未安装 flock，无法阻止多个菜单实例同时运行。"
        return 0
    fi
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    flock -n 9 || {
        die "另一个菜单实例正在运行：$LOCK_FILE"
        return 1
    }
}

ssh_context_warning() {
    [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" ]] || return 0
    local server_port=""
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        server_port="$(awk '{print $4}' <<< "$SSH_CONNECTION")"
    fi
    warn "检测到当前操作位于 SSH 会话中。"
    if [[ -n "$server_port" ]]; then
        warn "当前 SSH 服务端口可能为 $server_port，请先确认该端口已放行。"
    else
        warn "请先确认 SSH 服务端口已放行。"
    fi
}

require_command() {
    local cmd="${1:?missing command}"
    command -v "$cmd" >/dev/null 2>&1 || {
        die "缺少命令：$cmd"
        return 1
    }
}

resolve_core() {
    local candidate
    if [[ -n "$CORE_BIN" && -x "$CORE_BIN" ]]; then
        printf '%s\n' "$CORE_BIN"
        return 0
    fi
    for candidate in \
        "$(command -v ufw-docker 2>/dev/null || true)" \
        "$SCRIPT_DIR/ufw-docker" \
        "/usr/local/bin/ufw-docker"; do
        [[ -n "$candidate" && -x "$candidate" ]] || continue
        if [[ "$(readlink -f "$candidate" 2>/dev/null || printf '%s' "$candidate")" != \
              "$(readlink -f "$SCRIPT_PATH" 2>/dev/null || printf '%s' "$SCRIPT_PATH")" ]]; then
            CORE_BIN="$candidate"
            printf '%s\n' "$CORE_BIN"
            return 0
        fi
    done
    return 1
}

require_core() {
    resolve_core >/dev/null || {
        error "未找到 ufw-docker 核心命令。"
        say "请将 ufw-docker 与本菜单放在同一目录，或安装到 /usr/local/bin/ufw-docker。"
        return 1
    }
}

core_exec() {
    require_core || return 1
    run_cmd "$CORE_BIN" "$@"
}

resolve_helper() {
    local helper="${1:?missing helper}"
    local candidate
    for candidate in \
        "$SCRIPT_DIR/$helper" \
        "$INSTALL_HELPER_DIR/$helper" \
        "/usr/local/share/ufw-docker/$helper"; do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}

os_pretty_name() {
    if [[ -r /etc/os-release ]]; then
        (
            # shellcheck disable=SC1091
            . /etc/os-release
            printf '%s\n' "${PRETTY_NAME:-${NAME:-Linux}}"
        )
    else
        uname -s
    fi
}

ufw_state() {
    if ! command -v ufw >/dev/null 2>&1; then
        printf '未安装\n'
        return
    fi
    local output
    output="$(ufw status 2>/dev/null || true)"
    if grep -Fq 'Status: active' <<< "$output"; then
        printf '运行中\n'
    elif grep -Fq 'Status: inactive' <<< "$output"; then
        printf '未启用\n'
    else
        printf '不可用\n'
    fi
}

docker_state() {
    if ! command -v docker >/dev/null 2>&1; then
        printf '未安装\n'
    elif docker info >/dev/null 2>&1; then
        printf '运行中\n'
    else
        printf '不可用\n'
    fi
}

iptables_backend() {
    local output
    output="$(iptables --version 2>/dev/null || true)"
    if grep -Fq '(legacy)' <<< "$output"; then
        printf 'legacy\n'
    elif grep -Fq '(nf_tables)' <<< "$output"; then
        printf 'nf_tables\n'
    elif [[ -n "$output" ]]; then
        printf '%s\n' "$output"
    else
        printf '未知\n'
    fi
}

service_state() {
    if ! command -v systemctl >/dev/null 2>&1; then
        printf '非 systemd\n'
    elif systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        printf '运行中\n'
    elif systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        printf '已启用/未运行\n'
    else
        printf '未安装或未启用\n'
    fi
}
