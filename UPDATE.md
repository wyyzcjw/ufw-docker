# 菜单内 Root 更新

从 `1.5.0` 开始，主菜单 `00. 检查 / 更新菜单` 不再只是查看远程版本，还可以直接以 root 权限下载并安装新版本程序文件。

## 入口

```bash
sudo ufd
```

选择：

```text
00. 检查 / 更新菜单
```

更新中心提供：

```text
1. 重新检查远程版本
2. Root 直接下载安装稳定版（推荐）
3. Root 直接下载安装 master 开发版
4. 查看手动更新命令
0. 返回主菜单
```

## 稳定版更新

“稳定版”调用官方一键 bootstrap 的：

```text
--install --no-run
```

bootstrap 会优先读取 GitHub 最新 Release。如果当前仓库没有正式 Release，则按项目既有策略回退到 `master`。

## master 开发版

“master 开发版”调用：

```text
--install --no-run --dev
```

它会明确跳过 Release 检查并安装 `master` 当前内容，适合需要立即获取最新功能或修复时使用。

## Root 下载执行流程

菜单不会直接执行网络管道中的脚本。实际流程为：

```text
用户确认
  ↓
Root 创建 0700 临时目录
  ↓
从固定官方 raw.githubusercontent.com 地址下载 install.sh
  ↓
检查脚本中仓库身份 wyyzcjw/ufw-docker
  ↓
bash -n install.sh
  ↓
install.sh --self-test
  ↓
执行 install.sh --install --no-run [--dev]
  ↓
删除临时目录
  ↓
提示退出并重新运行 sudo ufd
```

Root 更新固定使用：

```text
https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh
```

`UFW_DOCKER_MENU_UPDATE_URL` 仍只用于远程 `VERSION` 检查，不会改变 Root 更新实际执行脚本的来源。

## 不会做什么

菜单内更新只更新程序文件，不会自动：

- 执行 `ufw enable`；
- 修改 `/etc/ufw/after.rules`；
- 删除已有 UFW-Docker allow/allow-ip 规则；
- 重启 UFW；
- 自动重启当前菜单进程。

更新完成后，当前进程仍运行旧代码。请退出并重新执行：

```bash
sudo ufd
```

## 手动更新

稳定通道：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --install --no-run
```

强制 master：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --install --dev --no-run
```

## 安全边界

这是一个明确的 root 代码更新功能，因此执行前仍需要人工确认。当前项目尚未建立 Release + SHA256/签名的完整发布链；现阶段通过固定官方 URL、仓库身份检查、Bash 语法检查和 bootstrap 自检降低风险。正式 Release 建立后，可继续加入 Release asset checksum/签名校验。
