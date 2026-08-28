# UFW-Docker 交互式菜单

`ufw-docker-menu` 是 `ufw-docker` 的纯 Bash 交互管理层。它不会复制或替代核心防火墙实现，而是负责环境检测、资源发现、参数校验、命令预览、危险操作确认和调用现有命令。

项目地址：<https://github.com/wyyzcjw/ufw-docker>

## 一键运行

在 Linux VPS 上可以直接执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh)
```

没有 `curl` 时：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh)
```

默认只下载临时副本并进入菜单，不会自动启用 UFW、修改规则或重启防火墙。退出菜单后临时目录自动清理。

永久安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --install
```

安装后直接运行：

```bash
sudo ufd
```

开发通道：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --dev
```

更多说明见 `ONE_CLICK_INSTALL.md`。

## 功能范围

菜单覆盖当前项目的主要能力：

- UFW、Docker、iptables 后端、systemd 服务和已管理规则总览；
- 响应式规则面板：手机卡片、紧凑表格、完整表格；
- 规则按容器分组、公开 `ANY` / 指定来源 / 异常规则筛选；
- UFW 目标 IP 与 Docker 当前容器地址健康检查；
- 自动列出运行中容器、容器端口、宿主机映射、Docker 网络和容器地址；
- 调用 `ufw-docker allow` 放行容器端口；
- 调用 `ufw-docker allow-ip` 按来源 IP/CIDR 放行；
- 调用核心 `list`，并额外支持基于 UFW 编号查看和删除带 `from:` 的规则；
- 增强重载普通规则和来源 IP 规则；
- `check`、`install`、`--docker-subnets` 和 `--system`；
- `install-service --force` 以及 systemd 服务管理；
- Docker Swarm 服务放行、删除和 `ufw-docker-agent` 查看；
- IPv4/IPv6 iptables 打印、数据包跟踪、UFW 日志和环境报告；
- 原始 UFW 命令与内部 `add-service-rule` 高级入口；
- 完整卸载和菜单自身安装/卸载。

## 环境要求

- Linux；
- Bash 4.3 或更高；
- root 或 sudo；
- Docker；
- UFW；
- `ufw-docker` 核心脚本；
- 自动重载服务管理需要 systemd。

菜单可以在依赖缺失时显示环境状态，但具体动作仍受核心命令的前置条件约束。

## 运行

在仓库目录中直接运行：

```bash
chmod +x ufw-docker ufw-docker-menu
sudo ./ufw-docker-menu
```

也可以指定核心脚本路径：

```bash
sudo UFW_DOCKER_BIN=/opt/ufw-docker/ufw-docker ./ufw-docker-menu
```

核心命令查找顺序：

1. `UFW_DOCKER_BIN`；
2. `PATH` 中的 `ufw-docker`；
3. 菜单同目录下的 `ufw-docker`；
4. `/usr/local/bin/ufw-docker`。

## 安装菜单快捷命令

```bash
sudo ./ufw-docker-menu --install-menu
```

安装后运行：

```bash
sudo ufw-docker-menu
```

或：

```bash
sudo ufd
```

安装位置：

```text
/usr/local/bin/ufw-docker
/usr/local/bin/ufw-docker-menu
/usr/local/bin/ufw-docker-rulectl
/usr/local/bin/ufd
/usr/local/share/doc/ufw-docker-menu/
/usr/local/lib/ufw-docker/
/usr/local/lib/ufw-docker-menu/
```

如果系统尚未安装核心命令，并且当前菜单来自完整仓库/一键下载包，菜单安装器会同时复制 `ufw-docker` 核心二进制。若系统已经存在 `/usr/local/bin/ufw-docker`，菜单选项 99 不会静默覆盖它；需要升级核心时建议重新执行一键安装的 `--install` 模式。

安装菜单和核心程序文件不会自动启用 UFW-Docker 防火墙规则。

## 主菜单

宽终端使用双列定位；窄终端自动切换为单列：

```text
1. 状态与规则总览                7. 安装与规则检查
2. 容器端口放行                  8. 自动重载服务管理
3. 指定来源 IP 放行              9. Docker Swarm 管理
4. 查询与删除规则               10. Docker 子网配置
5. 重载与修复规则               11. 诊断与调试工具
6. 容器/端口/网络信息           12. 帮助与项目说明

00. 检查菜单更新                90. 卸载 UFW-Docker
99. 安装菜单快捷命令            88. 退出
```

## 容器端口规则

菜单显示宿主机端口映射，但传给 `ufw-docker` 的是容器端口。

例如：

```text
宿主机 8080 -> 容器 80/tcp
```

实际执行：

```bash
ufw-docker allow nginx 80/tcp
```

不是：

```bash
ufw-docker allow nginx 8080/tcp
```

选择“全部已发布端口”时，菜单调用：

```bash
ufw-docker allow nginx
```

该操作会影响容器的全部已发布端口，因此执行前会显示额外警告。

## 指定来源 IP

支持单个 IP 和 CIDR：

```text
192.0.2.10
10.0.0.0/8
2001:db8::/64
```

示例命令：

```bash
ufw-docker allow-ip 192.0.2.10 nginx 80/tcp frontend
```

菜单优先使用 Python 标准库 `ipaddress` 校验 IP/CIDR；没有 Python 3 时使用保守的 Bash 格式校验。

当前核心 `allow-ip` 会遍历容器网络的 IPv4 和 IPv6 地址。菜单检测到双栈网络时会提示先在测试环境验证地址族行为。

## 规则视图、查询与删除

从 v1.4.0 起，默认规则页先解析 UFW-Docker 注释，不再直接把长 `ufw status numbered` 行作为主要界面。

自动视图规则：

```text
< 80 列      手机卡片
80-109 列    紧凑表格
>= 110 列    完整表格
```

手机卡片示例：

```text
[#30] hindsight  [正常]
  8888/tcp <- 104.224.155.35
  net hindsight_default
  dst 172.19.0.2
```

规则管理菜单提供：

1. 按容器分组查看；
2. 全部规则响应式列表；
3. 仅公开 `ANY` 规则；
4. 仅指定来源 IP/CIDR 规则；
5. 异常/失效规则；
6. 容器名称关键字搜索；
7. 删除规则；
8. Reload / 修复；
9. 原始 `ufw status numbered`；
10. 核心 CLI / `ufw-docker-rulectl` 高级入口。

菜单会比较 UFW 规则目标 IP 与 Docker 当前容器网络地址，并标记：`正常`、`IP已变化`、`容器不存在`、`容器已停止`、`Swarm` 或 `未验证`。

按编号删除时，菜单会先确认编号属于当前 UFW-Docker 已管理规则，避免把普通 UFW 规则误删。删除某容器全部规则时，容器选择列表来自已有规则，因此即使容器已经被删除，仍能清理遗留规则。

完整说明见 `RULE_VIEW.md`。

## 增强重载

增强重载识别以下注释：

```text
allow nginx 80/tcp frontend
allow nginx/v6 80/tcp frontend
allow nginx 80/tcp frontend from:192.0.2.10
allow nginx/v6 80/tcp frontend from:2001:db8::/64
```

IPv4 和 IPv6 同一逻辑规则会去重，然后分别调用：

```bash
ufw-docker allow ...
```

或：

```bash
ufw-docker allow-ip ...
```

如果重载失败，菜单只报告错误，不自动删除旧规则。Swarm 服务规则交给 `ufw-docker-agent` 重建。

## 安全措施

- 不使用 `eval`；
- 命令参数通过 Bash 数组传递；
- 规则修改前显示完整命令；
- 危险操作二次确认；
- 完整卸载要求输入 `UNINSTALL`；
- 通过 `flock` 阻止多个菜单实例同时修改规则；
- 检测 SSH 会话并提示当前服务端口；
- 不自动执行 `ufw enable`；
- 增强重载失败时不删除旧规则；
- 删除编号先验证属于 UFW-Docker 已管理规则；
- 更新功能只检查版本，不以 root 权限下载并覆盖脚本；
- raw UFW 入口不解释管道、重定向或命令替换。

远程服务器操作建议保留第二个 SSH 会话，并先确认 SSH 服务端口规则。

## 命令行参数

```bash
./ufw-docker-menu --help
./ufw-docker-menu --version
./ufw-docker-menu --print-main-menu
./ufw-docker-menu --self-test
sudo ./ufw-docker-menu --install-menu
sudo ./ufw-docker-menu --uninstall-menu
```

## 环境变量

```text
UFW_DOCKER_BIN
    指定 ufw-docker 核心脚本路径。

UFW_DOCKER_MENU_DRY_RUN=1
    只打印菜单发起的命令，不实际执行。

UFW_DOCKER_MENU_NO_AUTO_SUDO=1
    非 root 时不自动通过 sudo 重启。

UFW_DOCKER_MENU_LOCK_FILE
    覆盖默认锁文件路径。

UFW_DOCKER_MENU_UPDATE_URL
    覆盖只读版本检查地址。

UFW_DOCKER_MENU_RULE_VIEW
    强制规则视图：auto、card、compact 或 full。

UFW_DOCKER_MENU_RULE_HEALTH_CHECK=0
    关闭 Docker 实时规则健康检查，只显示规则结构。

UFW_DOCKER_MENU_TESTING=1
    测试模式，跳过暂停、root 检查和锁。

NO_COLOR=1
    禁用 ANSI 颜色。
```

## 测试

语法检查和内置测试：

```bash
bash -n ufw-docker-menu
NO_COLOR=1 UFW_DOCKER_MENU_TESTING=1 ./ufw-docker-menu --self-test
bash -n install.sh
bash install.sh --self-test
bash test/rule-view.test.sh
```

项目测试入口会自动执行新增的测试文件：

```bash
./test.sh
```

## 卸载菜单

```bash
sudo ufw-docker-menu --uninstall-menu
```

该命令只卸载菜单和生命周期辅助工具，不自动删除 `/usr/local/bin/ufw-docker` 核心程序。

完整卸载 UFW-Docker 请运行菜单并选择：

```text
90. 卸载 UFW-Docker
```
