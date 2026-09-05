# Alpine Linux 安装

新增 `scripts/install_alpine.sh`，使用 POSIX sh、apk 和 OpenRC，从当前源码编译内核模块，不依赖 DKMS、Bash 或 GNU grep。适用于使用自身 Linux 内核且允许加载模块的 VPS/实体机；Docker/LXC 应在宿主机安装。

目标环境：Alpine 3.24.1 / x86_64 / 6.18.38-0-virt。

## 安装

解压本项目后，以 root 在项目目录执行：

```sh
sh scripts/install_alpine.sh
```

脚本自动安装 build-base、kmod；缺少当前内核开发文件时，virt 内核安装 linux-virt-dev，lts 内核安装 linux-lts-dev。它会核对开发文件的 kernel.release 和模块 vermagic，安装到当前内核的 extra 目录，执行 depmod/modprobe，并配置 OpenRC modules 服务开机加载。

如果提示开发文件与正在运行的内核不匹配，不要创建假软链接。先检查 apk 仓库与系统版本一致，再执行：

```sh
apk upgrade linux-virt linux-virt-dev
reboot
```

重启后重新执行安装脚本。lts 系统将上面的两个包名替换为 linux-lts / linux-lts-dev。此脚本不提供内核升级自动重建；每次升级内核并重启后都要重新执行。已加载 brutal 时脚本会停止，需先停止使用它的应用，再执行 `rmmod brutal` 后重试。

## 检查及卸载

```sh
lsmod | grep brutal
modinfo brutal
sh scripts/install_alpine.sh uninstall
```

卸载仅移除当前内核版本的模块和 brutal 开机加载配置；不移除编译依赖，也不关闭系统 modules 服务。

本安装器仅安装内核模块。按原项目文档配置支持 TCP Brutal 的应用及带宽；不修改默认拥塞控制。需要 v2 的 brutalctl 管理工具时，可以另行 `make -C tools` 编译。

## 验证范围

已完成 shell 语法、帮助入口、非 Alpine 平台拒绝检查。附带 GitHub Actions 工作流在 Alpine 3.24 x86_64 环境中编译 linux-virt 模块和 brutalctl；交付时尚未运行此工作流，也尚未在目标 VPS 加载或测速。容器编译成功不能替代 VPS 实际加载验证。

## 独立 Bash 安装入口

以 root 运行（重启后也可以重复使用）：

```sh
apk add --no-cache bash curl ca-certificates
curl -fL https://raw.githubusercontent.com/akaagiao1/tcp-brutal/master/scripts/alpine.sh -o alpine.sh
bash alpine.sh
```

此入口自动下载固定提交的模块源码并清理临时目录。默认从本 fork 下载 Alpine 安装器；不自动升级内核或重启。卸载使用 `bash alpine.sh uninstall`。
