# UFW-Docker 一键运行与安装

本仓库提供 `install.sh` 网络引导脚本，用于在 VPS 上通过一条命令下载项目并进入交互菜单。

## 一键运行

推荐命令：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh)
```

没有 `curl` 时也可以使用：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh)
```

默认行为：

1. 检测 Linux、Bash 版本、`curl`/`wget` 和 `tar`；
2. 优先查询最新 GitHub Release；
3. 如果仓库尚未发布 Release，则回退到 `master`；
4. 下载完整项目到权限收紧的临时目录；
5. 校验 tar 包能否正常读取；
6. 检查菜单、核心脚本、生命周期模块等必需文件；
7. 对 Shell 脚本执行 `bash -n`；
8. 执行菜单内置 `--self-test`；
9. 通过 root/sudo 启动交互菜单；
10. 退出后自动删除临时目录。

默认一键运行不会自动执行 `ufw enable`，不会自动修改 `/etc/ufw/after.rules`，也不会自动重启 UFW。防火墙修改仍需要在菜单中明确选择并确认。

## 永久安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --install
```

该模式会先复制程序文件到系统目录，然后启动菜单。

安装后的主要命令：

```text
/usr/local/bin/ufw-docker
/usr/local/bin/ufw-docker-menu
/usr/local/bin/ufw-docker-rulectl
/usr/local/bin/ufd
```

之后可以直接执行：

```bash
sudo ufd
```

`--install` 只安装程序文件，不会自动安装 UFW-Docker 防火墙规则。需要启用核心规则时，请在菜单中进入“安装与规则检查”。

## 开发通道

强制使用 `master`：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --dev
```

稳定通道在有 GitHub Release 后会优先使用最新 Release；目前仓库没有 Release 时会自动回退至 `master` 并显示提示。

## 指定版本 / Ref

例如指定 tag：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --ref v1.3.0
```

指定 commit SHA：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --ref <commit-sha>
```

复杂分支名建议传入完整 ref，例如：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --ref refs/heads/feature/example
```

## 只安装、不启动菜单

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --install --no-run
```

## 保留临时文件用于调试

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wyyzcjw/ufw-docker/master/install.sh) --keep-temp
```

## 自检

本地仓库中：

```bash
bash -n install.sh
bash install.sh --self-test
```

完整项目测试：

```bash
./test.sh
```

## 安全设计

- 引导脚本只从本项目的 GitHub HTTPS 地址下载；
- 支持 `curl` 和 `wget`，不依赖 `jq`；
- 使用 `mktemp` 创建临时工作区并在退出时清理；
- 解压前检查 tar.gz 可读性；
- 下载后检查关键文件是否齐全；
- 对菜单和模块执行 Bash 语法检查；
- 启动前执行菜单自检；
- 非 root 用户通过 `sudo` 运行需要权限的阶段；
- 一键运行不会静默修改防火墙；
- 当前尚未建立 Release + SHA256 签名发布链，因此稳定通道无 Release 时回退 `master`。建立正式 Release 后可继续加入 checksum 校验。
