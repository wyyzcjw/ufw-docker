# UFW-Docker 交互菜单

`ufw-docker-menu` 是 `ufw-docker` 的纯 Bash 交互前端，菜单风格参考常见 VPS 一键脚本，但不复制核心防火墙实现。

## 目标

- 保留原有 `ufw-docker` CLI，方便自动化、脚本和 CI 使用。
- 增加交互式容器、端口、网络、来源 IP/CIDR 选择。
- 对修改操作统一展示最终命令并二次确认。
- 提供规则查询/删除、reload、安装/check、systemd、Swarm、子网和调试工具入口。
- 不使用 `eval`，不自动执行 `ufw enable`，不静默重启 UFW。

## 安装菜单

在仓库目录：

```bash
sudo ./install-menu.sh
sudo ufd
```

也可以直接运行：

```bash
sudo ./ufw-docker-menu
```

如果 `ufw-docker` 不在 PATH，可指定：

```bash
sudo UFW_DOCKER_BIN=/path/to/ufw-docker ./ufw-docker-menu
```

## 菜单覆盖范围

1. 状态与规则总览
2. 容器端口放行
3. 指定来源 IP/CIDR 放行（`allow-ip`）
4. 查询与删除规则
5. 规则 reload
6. 容器 / 端口 / 网络信息
7. `check` / `install`
8. `install-service` 与 systemd 管理
9. Docker Swarm service allow/delete
10. Docker 子网配置
11. `print-iptables*` / `trace-iptables*` 等诊断工具
12. 帮助与安全说明

## 安全说明

`ufw-docker` 使用容器端口。例如 Docker 映射为 `8080:80` 时，应选择 `80/tcp`，而不是宿主机端口 `8080`。

安装和卸载会修改系统防火墙配置。建议保留当前 SSH 会话，在另一个终端验证 SSH 端口仍可访问后再断开连接。

调试 trace 脚本会在 iptables/ip6tables 链中插入日志规则，仅用于临时排障。完成后应通过菜单移除。

## 当前限制

当前 fork 已提供 `allow-ip`，但来源 IP/CIDR 规则的 `list/delete/reload` 生命周期仍未完全进入核心命令统一解析。菜单因此采用 **UFW 编号删除** 作为安全兜底，并明确提示 `reload` 的限制。

后续建议把核心规则 comment 解析升级为统一结构，原生支持：

- 普通规则：`allow <container> <port/proto> <network>`
- 来源规则：`allow <container> <port/proto> <network> from:<CIDR>`

然后让 `list`、`delete` 和 `reload` 共用同一个解析器。
