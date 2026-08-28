# UFW-Docker 规则视图

从 v1.4.0 起，交互菜单不再把 `ufw status numbered` 的长行作为默认规则展示，而是先解析 UFW-Docker 注释，再按终端宽度呈现结构化视图。

## 响应式显示

默认 `UFW_DOCKER_MENU_RULE_VIEW=auto`：

- 小于 80 列：手机卡片视图；
- 80–109 列：紧凑表格；
- 110 列及以上：完整表格。

可以手动覆盖：

```bash
UFW_DOCKER_MENU_RULE_VIEW=card sudo ufd
UFW_DOCKER_MENU_RULE_VIEW=compact sudo ufd
UFW_DOCKER_MENU_RULE_VIEW=full sudo ufd
```

卡片视图优先显示：

```text
[#30] hindsight  [正常]
  8888/tcp <- 104.224.155.35
  net hindsight_default
  dst 172.19.0.2
```

其中：

- `dst` 是 UFW 规则当前指向的容器 IP；
- `ANY` 表示规则没有来源限制；
- 指定 IP/CIDR 来源会直接显示在箭头右侧；
- IPv6 规则在端口后标记 `v6`。

## 规则管理菜单

主菜单 `4. 查询与删除规则` 提供：

1. 按容器分组查看规则；
2. 全部规则的响应式列表；
3. 仅查看公开 `ANY` 规则；
4. 仅查看指定来源 IP/CIDR 规则；
5. 仅查看异常/失效规则；
6. 按容器名称关键字搜索；
7. 安全删除 UFW-Docker 已管理规则；
8. 进入 Reload / 修复菜单；
9. 查看原始 `ufw status numbered`；
10. 进入核心 CLI / `ufw-docker-rulectl` 高级入口。

按编号删除时会先验证编号属于当前 UFW-Docker 已管理规则，避免误删普通 UFW 规则。

## 状态页

`1. 状态与规则总览` 不再重复打印核心 `ufw-docker status` 与原始 UFW 长行，而是显示：

- UFW-Docker 规则记录数量；
- 涉及容器数量；
- `ANY` 公开规则数量；
- 指定来源规则数量；
- IPv4 / IPv6 数量；
- 正常、异常、未验证规则数量；
- 最近 4 条规则。

原始 UFW 输出仍可从规则管理菜单查看。

## 规则健康检查

菜单会把 UFW 规则的目标 IP 与 Docker 当前网络地址进行比较。

状态含义：

- `正常`：UFW 目标 IP 与容器当前 IP 一致；
- `IP已变化`：容器仍在运行，但 UFW 目标 IP 已不是当前地址；
- `容器不存在`：规则指向的容器已不存在；
- `容器已停止`：容器存在但当前未运行；
- `Swarm`：识别为 Docker Swarm service，由 `ufw-docker-agent` 管理；
- `未验证`：Docker 当前不可用，或目标地址无法可靠验证；
- `未检测`：用户显式关闭了健康检查。

如果服务器容器很多、希望只看规则而不执行 Docker 健康检查：

```bash
UFW_DOCKER_MENU_RULE_HEALTH_CHECK=0 sudo ufd
```

## 颜色语义

在支持 ANSI 颜色的终端中：

- 绿色：正常状态、指定来源；
- 黄色：`ANY` 公开访问；
- 青色：容器名、Docker 网络；
- 蓝色：目标 IP；
- 紫色：端口；
- 红色：IP 变化、容器不存在等异常；
- 灰色：未验证或次要信息。

设置 `NO_COLOR=1` 可以关闭颜色。
