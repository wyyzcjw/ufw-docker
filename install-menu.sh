#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd -P)"
menu="${script_dir}/ufw-docker-menu"

[[ -r "$menu" ]] || {
    echo "Cannot find $menu" >&2
    exit 1
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo -E bash "$menu" --install-menu
    fi
    echo "Please run as root: sudo ./install-menu.sh" >&2
    exit 1
fi

exec bash "$menu" --install-menu
