# UFW-Docker Interactive Manager

基于 [chaifeng/ufw-docker](https://github.com/chaifeng/ufw-docker) 的增强版，增加交互式管理菜单、来源 IP/CIDR 规则生命周期管理、响应式规则面板、诊断工具，以及适合 VPS 使用的一键下载运行方式。

当前工具版本：`1.4.0`

## 一键运行

Linux VPS 上直接执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh)
```

没有 `curl` 时：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh)
```

默认模式会下载临时副本、完成完整性和 Shell 语法检查，然后进入交互菜单。退出后自动清理临时目录。

> 一键运行本身不会自动执行 `ufw enable`、不会自动修改 UFW 规则，也不会自动重启防火墙。真正的防火墙变更仍需要在菜单中明确选择并确认。

## 永久安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --install
```

安装完成后：

```bash
sudo ufd
```

主要安装路径：

```text
/usr/local/bin/ufw-docker
/usr/local/bin/ufw-docker-menu
/usr/local/bin/ufw-docker-rulectl
/usr/local/bin/ufd
```

只安装、不立即进入菜单：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --install --no-run
```

## 开发通道 / 指定版本

强制使用 `master`：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --dev
```

指定 tag、commit 或 ref：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --ref <tag-or-commit>
```

当前仓库尚未建立正式 GitHub Release，因此默认稳定通道会暂时回退到 `master`。未来建立 Release 后，同一条一键命令会优先下载最新稳定 Release。

## 交互菜单

主菜单覆盖当前项目已经实现的核心功能：

```text
1. 状态与规则总览                7. 安装与规则检查
2. 容器端口放行                  8. 自动重载服务管理
3. 指定来源 IP/CIDR 放行         9. Docker Swarm 管理
4. 查询与删除规则               10. Docker 子网配置
5. 重载与修复规则               11. 诊断与调试工具
6. 容器/端口/网络信息           12. 帮助与项目说明

00. 检查菜单更新                90. 卸载 UFW-Docker
99. 安装菜单快捷命令            88. 退出
```

菜单会自动发现 Docker 容器、已发布端口、宿主机映射、Docker 网络和容器地址。传给 `ufw-docker` 的始终是**容器端口**，而不是宿主机映射端口。

### 响应式规则面板

规则不再默认直接打印 `ufw status numbered` 的长行。菜单会解析容器、端口、来源、Docker 网络和目标 IP，并根据终端宽度自动切换：

```text
< 80 列      手机卡片视图
80-109 列    紧凑表格
>= 110 列    完整表格
```

规则页支持按容器分组、只看 `ANY` 公开规则、只看指定来源规则、搜索容器以及查看异常规则。菜单还会比较 UFW 目标 IP 与 Docker 当前地址，提示 `IP已变化`、`容器不存在` 或 `容器已停止` 等状态。

## 主要增强

- `ufw-docker allow` 图形化/菜单化操作；
- `allow-ip` 按来源 IP 或 CIDR 精确放行；
- 普通规则和 `from:<SOURCE>` 规则统一查询、删除和重载；
- 手机卡片 / 紧凑表格 / 完整表格响应式规则视图；
- 按容器分组、公开规则、指定来源规则和异常规则筛选；
- UFW 目标 IP 与 Docker 当前地址健康检查；
- 删除前校验 UFW 编号确属 UFW-Docker 已管理规则；
- `ufw-docker-rulectl` 提供稳定 TSV 输出；
- IPv4/IPv6 规则解析和逻辑去重；
- Docker Swarm service allow/delete；
- Docker 子网自动检测与自定义；
- systemd 自动重载服务管理；
- iptables/ip6tables 递归查看和 packet trace；
- UFW 日志和环境诊断；
- 原始 `raw-command`、`add-service-rule` 高级入口；
- 命令执行前预览、危险操作确认、SSH 会话提醒；
- 不使用 `eval`。

## 环境要求

- Linux；
- Bash 4.3+；
- Docker；
- UFW；
- root 或 sudo；
- 自动重载服务功能需要 systemd。

## 测试

```bash
./test.sh
```

一键引导脚本也可以独立自检：

```bash
bash -n install.sh
bash install.sh --self-test
```

## 文档

- [交互菜单说明](MENU.md)
- [规则视图与健康检查](RULE_VIEW.md)
- [一键安装详细说明](ONE_CLICK_INSTALL.md)
- [来源 IP 规则生命周期](RULE_LIFECYCLE.md)
- [核心命令菜单覆盖表](COMMAND_COVERAGE.md)
- [原始上游 README](README_UPSTREAM.md)

## 关于上游

本仓库继续保留 `chaifeng/ufw-docker` 的核心防火墙设计，并尽量减少对上游核心逻辑的侵入，以便后续同步上游更新。原始项目的详细原理、iptables/UFW 说明和历史文档已完整保存在 [README_UPSTREAM.md](README_UPSTREAM.md)。

## License

GPL-3.0，沿用上游项目许可证。
