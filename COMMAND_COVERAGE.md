# UFW-Docker Menu Command Coverage

The interactive menu is designed to expose every command that is actually implemented by this fork while keeping the `ufw-docker` core as the firewall source of truth.

| Core command | Menu location | Notes |
|---|---|---|
| `status` | 1. 状态与规则总览 | Also shows Docker/UFW/backend/service state. |
| `list` | 4. 查询与删除规则 | Includes source-aware lifecycle view. |
| `allow` | 2. 容器端口放行 | Container/port/network are selected interactively. |
| `allow-ip` | 3. 指定来源 IP 放行 | Supports source IP/CIDR validation. |
| `delete allow` | 4. 查询与删除规则 | Uses safe numbered deletion for source-aware rules. |
| `reload` | 5. 重载与修复规则 | Shared lifecycle parser handles normal + `from:` rules. |
| `check` | 7. 安装与规则检查 | Default, Docker-subnet and custom-subnet modes. |
| `install` | 7. 安装与规则检查 | Destructive preview + confirmation. |
| `install-service` | 8. 自动重载服务管理 | Includes `--force` and systemd status/start/stop/restart/logs. |
| `service allow` | 9. Docker Swarm 管理 | Service and TargetPort are selected interactively. |
| `service delete allow` | 9. Docker Swarm 管理 | Whole-service or selected-port removal. |
| `uninstall` | 90. 卸载 UFW-Docker | Requires exact `UNINSTALL` confirmation. |
| `help` | 11 -> 13 -> 1 | Raw core help. |
| `man` / `manpage` | 11 -> 13 -> 2 | Raw core man page. |
| `raw-command` | 11 -> 13 -> 3 | Arguments are passed as a Bash array; no `eval`. |
| `add-service-rule` | 11 -> 13 -> 4 | Marked internal/high-risk; normal users should use Swarm menu. |

Additional project utilities are also exposed:

- `print-iptables.sh`
- `print-ip6tables.sh`
- `trace-iptables.sh add/remove`
- `trace-ip6tables.sh add/remove`
- UFW log view
- environment diagnostics
- `ufw-docker-rulectl` TSV view and reload preview

## Important distinction: `deny`

The current core dispatcher does **not** implement a container-level `deny` command even though the inherited man page still mentions `allow|deny` in a few places. The menu intentionally does not invent a `deny` operation that the core does not have. If container-level deny is added to the core later, it should receive its own tested menu path.

## Safety model

The menu does not translate selections into raw iptables rules. It calls the existing core commands, with the source-aware lifecycle helper used only for parsing/listing/deleting/reloading the fork's managed UFW comments. This keeps firewall behavior centralized and reduces divergence from upstream `chaifeng/ufw-docker`.
