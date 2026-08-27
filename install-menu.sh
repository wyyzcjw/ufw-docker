#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Please run as root: sudo ./install-menu.sh" >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd -P)"
src="${script_dir}/ufw-docker-menu"
dst="/usr/local/bin/ufw-docker-menu"
shortcut="/usr/local/bin/ufd"
asset_dir="/usr/local/lib/ufw-docker"

[[ -f "$src" ]] || {
    echo "Cannot find $src" >&2
    exit 1
}

install -m 0755 "$src" "$dst"
ln -sfn "$dst" "$shortcut"

mkdir -p "$asset_dir"
for name in print-iptables.sh print-ip6tables.sh trace-iptables.sh trace-ip6tables.sh; do
    if [[ -f "${script_dir}/${name}" ]]; then
        install -m 0755 "${script_dir}/${name}" "${asset_dir}/${name}"
    fi
done

echo "Installed:"
echo "  $dst"
echo "  $shortcut -> $dst"
echo "  diagnostics -> $asset_dir"
echo
echo "Run with:"
echo "  sudo ufd"
