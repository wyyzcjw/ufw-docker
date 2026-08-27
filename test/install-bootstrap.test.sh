#!/usr/bin/env bash
set -euo pipefail

working_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd -P)"
root_dir="${working_dir}/.."
bootstrap="${root_dir}/install.sh"

bash -n "$bootstrap"

help_output="$(NO_COLOR=1 bash "$bootstrap" --help)"
grep -Fq -- '--install' <<< "$help_output"
grep -Fq -- '--dev' <<< "$help_output"
grep -Fq -- '--ref REF' <<< "$help_output"
grep -Fq -- '--no-run' <<< "$help_output"

[[ "$(NO_COLOR=1 bash "$bootstrap" --version)" == "1.0.0" ]]
NO_COLOR=1 bash "$bootstrap" --self-test | grep -Fq 'bootstrap self-test passed'

printf 'install bootstrap tests passed\n'
