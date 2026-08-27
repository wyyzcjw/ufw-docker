#!/usr/bin/env bash
set -euo pipefail

working_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd -P)"
menu="${working_dir}/../ufw-docker-menu"

bash -n "$menu"

UFW_DOCKER_MENU_LIB_ONLY=1 NO_COLOR=1 source "$menu"

validate_source "1.2.3.4"
validate_source "10.0.0.0/8"
validate_source "2001:db8::1"
validate_source "2001:db8::/64"

! validate_source ""
! validate_source "1.2.3.4;rm"
! validate_source "example.com"

validate_port_proto "80"
validate_port_proto "443/tcp"
validate_port_proto "53/udp"
! validate_port_proto "tcp/80"
! validate_port_proto "80/sctp"

validate_cidr_token "10.0.0.0/8"
validate_cidr_token "fd00::/8"
! validate_cidr_token "10.0.0.1"

joined="$(shell_join ufw-docker allow "my container" 80/tcp)"
[[ "$joined" == *"ufw-docker"* ]]
[[ "$joined" == *"my\\ container"* ]]

printf "ufw-docker-menu tests passed\n"
