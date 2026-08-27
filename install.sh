#!/usr/bin/env bash
# One-click bootstrap for wyyzcjw/ufw-docker.
# Safe default: download and launch the interactive menu without changing UFW rules.

set -Eeuo pipefail

BOOTSTRAP_VERSION="1.0.0"
REPO="wyyzcjw/ufw-docker"
DEFAULT_BRANCH="master"
RAW_INSTALL_URL="https://raw.githubusercontent.com/${REPO}/${DEFAULT_BRANCH}/install.sh"
API_LATEST_RELEASE="https://api.github.com/repos/${REPO}/releases/latest"
MODE="run"
CHANNEL="stable"
CUSTOM_REF=""
NO_RUN=0
KEEP_TEMP=0
TMP_DIR=""
SRC_DIR=""
DOWNLOADER=""

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
    C_RED=$'\033[1;31m'
    C_CYAN=$'\033[1;36m'
else
    C_RESET="" C_BOLD="" C_GREEN="" C_YELLOW="" C_RED="" C_CYAN=""
fi

info() { printf '%s[信息]%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
success() { printf '%s[成功]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[警告]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
fatal() { printf '%s[错误]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
UFW-Docker 一键引导脚本 v${BOOTSTRAP_VERSION}

用法：
  bash <(curl -fsSL ${RAW_INSTALL_URL})
  bash <(curl -fsSL ${RAW_INSTALL_URL}) --install
  bash <(curl -fsSL ${RAW_INSTALL_URL}) --dev

选项：
  --install       永久安装 ufw-docker、菜单和辅助工具，然后进入菜单
  --dev           直接使用 master 开发分支，不检查 GitHub Release
  --ref REF       下载指定 ref；建议使用 tag、commit SHA 或 refs/heads/xxx
  --no-run        下载/安装完成后不自动进入菜单
  --keep-temp     退出时保留临时下载目录，便于调试
  --self-test     只执行本引导脚本的本地自检，不访问网络
  --version, -V   显示引导脚本版本
  --help, -h      显示帮助

说明：
  默认模式只下载临时副本并启动交互菜单，不会自动启用 UFW、修改规则或重启防火墙。
  稳定通道优先使用最新 GitHub Release；仓库尚无 Release 时自动回退到 master。
EOF
}

cleanup() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        if [[ "$KEEP_TEMP" == "1" ]]; then
            warn "已保留临时目录：$TMP_DIR"
        else
            rm -rf -- "$TMP_DIR" || true
        fi
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

require_linux() {
    [[ "$(uname -s 2>/dev/null || true)" == "Linux" ]] || fatal "仅支持 Linux。"
}

require_bash() {
    if (( BASH_VERSINFO[0] < 4 )) || (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3 )); then
        fatal "需要 Bash >= 4.3，当前版本为 ${BASH_VERSION}。"
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fatal "缺少命令：$1"
}

select_downloader() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
    else
        fatal "需要 curl 或 wget。"
    fi
}

download_stdout() {
    local url="$1"
    case "$DOWNLOADER" in
        curl) curl -fsSL --retry 3 --connect-timeout 10 "$url" ;;
        wget) wget -qO- --timeout=10 --tries=3 "$url" ;;
        *) return 1 ;;
    esac
}

download_file() {
    local url="$1" destination="$2"
    case "$DOWNLOADER" in
        curl) curl -fL --retry 3 --connect-timeout 10 --progress-bar -o "$destination" "$url" ;;
        wget) wget --timeout=10 --tries=3 -O "$destination" "$url" ;;
        *) return 1 ;;
    esac
}

latest_release_tag() {
    local json tag
    json="$(download_stdout "$API_LATEST_RELEASE" 2>/dev/null || true)"
    [[ -n "$json" ]] || return 1
    tag="$(printf '%s\n' "$json" | sed -n 's/^[[:space:]]*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    [[ -n "$tag" ]] || return 1
    printf '%s\n' "$tag"
}

validate_ref() {
    local ref="${1:-}"
    [[ -n "$ref" ]] || return 1
    [[ "$ref" =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
    [[ "$ref" != /* && "$ref" != *..* ]] || return 1
}

resolve_download() {
    local release_tag

    if [[ -n "$CUSTOM_REF" ]]; then
        validate_ref "$CUSTOM_REF" || fatal "--ref 包含不安全或不支持的字符：$CUSTOM_REF"
        RESOLVED_REF="$CUSTOM_REF"
        RESOLVED_CHANNEL="custom"
        ARCHIVE_URL="https://codeload.github.com/${REPO}/tar.gz/${CUSTOM_REF}"
        return 0
    fi

    if [[ "$CHANNEL" == "dev" ]]; then
        RESOLVED_REF="$DEFAULT_BRANCH"
        RESOLVED_CHANNEL="dev"
        ARCHIVE_URL="https://github.com/${REPO}/archive/refs/heads/${DEFAULT_BRANCH}.tar.gz"
        return 0
    fi

    if release_tag="$(latest_release_tag)"; then
        RESOLVED_REF="$release_tag"
        RESOLVED_CHANNEL="release"
        ARCHIVE_URL="https://github.com/${REPO}/archive/refs/tags/${release_tag}.tar.gz"
    else
        RESOLVED_REF="$DEFAULT_BRANCH"
        RESOLVED_CHANNEL="stable-fallback"
        ARCHIVE_URL="https://github.com/${REPO}/archive/refs/heads/${DEFAULT_BRANCH}.tar.gz"
        warn "当前仓库没有可用 GitHub Release，稳定通道暂时回退到 master。"
    fi
}

create_workspace() {
    umask 077
    TMP_DIR="$(mktemp -d -t ufw-docker.XXXXXXXX)"
    SRC_DIR="$TMP_DIR/source"
    mkdir -p "$SRC_DIR"
}

verify_archive_and_extract() {
    local archive="$1"
    require_command tar
    tar -tzf "$archive" >/dev/null 2>&1 || fatal "下载文件不是有效的 tar.gz。"
    tar -xzf "$archive" -C "$SRC_DIR" --strip-components=1

    local required
    for required in \
        ufw-docker \
        ufw-docker-menu \
        VERSION \
        lib/ufw-docker-menu/common.sh \
        lib/ufw-docker-menu/app.sh \
        lib/ufw-docker-menu/extras.sh \
        lib/ufw-docker-menu/installer.sh \
        lib/ufw-docker-rules.sh; do
        [[ -r "$SRC_DIR/$required" ]] || fatal "下载内容不完整，缺少：$required"
    done

    chmod +x "$SRC_DIR/ufw-docker" "$SRC_DIR/ufw-docker-menu" 2>/dev/null || true
    [[ ! -f "$SRC_DIR/ufw-docker-rulectl" ]] || chmod +x "$SRC_DIR/ufw-docker-rulectl" 2>/dev/null || true

    bash -n "$SRC_DIR/ufw-docker"
    bash -n "$SRC_DIR/ufw-docker-menu"
    local module
    for module in "$SRC_DIR"/lib/ufw-docker-menu/*.sh "$SRC_DIR/lib/ufw-docker-rules.sh"; do
        bash -n "$module"
    done

    NO_COLOR=1 UFW_DOCKER_MENU_TESTING=1 "$SRC_DIR/ufw-docker-menu" --self-test >/dev/null
}

run_as_root() {
    if (( EUID == 0 )); then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo -E "$@"
    else
        fatal "该操作需要 root 权限，且系统未安装 sudo。请切换到 root 后重试。"
    fi
}

install_persistent() {
    require_command install
    info "正在安装核心命令和交互菜单..."
    run_as_root install -d -m 0755 /usr/local/bin
    run_as_root install -m 0755 "$SRC_DIR/ufw-docker" /usr/local/bin/ufw-docker
    run_as_root bash "$SRC_DIR/ufw-docker-menu" --install-menu

    success "已安装 /usr/local/bin/ufw-docker"
    success "已安装 /usr/local/bin/ufw-docker-menu"
    success "快捷命令：/usr/local/bin/ufd"
    info "永久安装只复制程序文件，不会自动修改 UFW 规则。"
}

launch_menu() {
    local menu="$1"
    info "正在启动 UFW-Docker 交互菜单..."
    if (( EUID == 0 )); then
        "$menu"
    elif command -v sudo >/dev/null 2>&1; then
        sudo -E "$menu"
    else
        "$menu"
    fi
}

self_test() {
    local failed=0
    [[ "$REPO" == "wyyzcjw/ufw-docker" ]] || failed=1
    [[ "$RAW_INSTALL_URL" == https://raw.githubusercontent.com/* ]] || failed=1
    [[ "$API_LATEST_RELEASE" == https://api.github.com/* ]] || failed=1
    validate_ref "v1.3.0" || failed=1
    validate_ref "refs/heads/feature/example" || failed=1
    validate_ref "abcdef0123456789" || failed=1
    if validate_ref "https://example.com/x"; then failed=1; fi
    declare -F download_file >/dev/null || failed=1
    declare -F resolve_download >/dev/null || failed=1
    declare -F verify_archive_and_extract >/dev/null || failed=1
    declare -F install_persistent >/dev/null || failed=1
    if (( failed == 0 )); then
        printf 'bootstrap self-test passed\n'
        return 0
    fi
    printf 'bootstrap self-test failed\n' >&2
    return 1
}

parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            --install)
                MODE="install"
                ;;
            --dev)
                CHANNEL="dev"
                ;;
            --ref)
                (( $# >= 2 )) || fatal "--ref 缺少参数。"
                CUSTOM_REF="$2"
                shift
                ;;
            --no-run)
                NO_RUN=1
                ;;
            --keep-temp)
                KEEP_TEMP=1
                ;;
            --self-test)
                self_test
                exit $?
                ;;
            --version|-V)
                printf '%s\n' "$BOOTSTRAP_VERSION"
                exit 0
                ;;
            --help|-h|help)
                usage
                exit 0
                ;;
            *)
                fatal "未知参数：$1"
                ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"
    require_linux
    require_bash
    select_downloader
    create_workspace
    resolve_download

    printf '%sUFW-Docker One-Click Bootstrap%s\n' "$C_BOLD" "$C_RESET"
    printf '仓库：%s\n' "$REPO"
    printf '通道：%s\n' "$RESOLVED_CHANNEL"
    printf '版本/Ref：%s\n\n' "$RESOLVED_REF"

    local archive="$TMP_DIR/ufw-docker.tar.gz"
    info "下载：$ARCHIVE_URL"
    download_file "$ARCHIVE_URL" "$archive" || fatal "下载失败。"

    info "校验并解压下载内容..."
    verify_archive_and_extract "$archive"
    success "下载内容校验通过。"

    if [[ "$MODE" == "install" ]]; then
        install_persistent
        if [[ "$NO_RUN" != "1" ]]; then
            launch_menu /usr/local/bin/ufw-docker-menu
        fi
    elif [[ "$NO_RUN" != "1" ]]; then
        launch_menu "$SRC_DIR/ufw-docker-menu"
    else
        info "--no-run 已启用，未启动菜单。临时目录退出时会自动清理。"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
