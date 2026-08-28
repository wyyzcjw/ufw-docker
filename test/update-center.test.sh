#!/usr/bin/env bash
set -euo pipefail

working_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd -P)"
root_dir="${working_dir}/.."
menu="${root_dir}/ufw-docker-menu"

export NO_COLOR=1
export UFW_DOCKER_MENU_TESTING=1
export UFW_DOCKER_MENU_NO_PYTHON=1
# shellcheck disable=SC1090
source "$menu"

declare -F check_updates >/dev/null
declare -F root_update_from_github >/dev/null
declare -F update_download_file >/dev/null
declare -F update_remote_version >/dev/null

grep -Fq 'https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh' \
    "$root_dir/lib/ufw-docker-menu/updater.sh"

grep -Fq 'REPO=\"wyyzcjw/ufw-docker\"' \
    "$root_dir/lib/ufw-docker-menu/updater.sh"

version_is_newer 2.0.0 1.9.9
version_is_newer v1.5.1 1.5.0
! version_is_newer 1.5.0 1.5.0
! version_is_newer 1.4.9 1.5.0

mapfile -t stable_args < <(root_update_build_args stable)
[[ "${stable_args[*]}" == "--install --no-run" ]]
mapfile -t dev_args < <(root_update_build_args dev)
[[ "${dev_args[*]}" == "--install --no-run --dev" ]]

manual="$(show_manual_update_commands)"
grep -Fq -- '--install --no-run' <<< "$manual"
grep -Fq -- '--install --dev --no-run' <<< "$manual"

printf 'update center tests passed\n'
