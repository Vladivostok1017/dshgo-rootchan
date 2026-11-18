# dshgo-rootchan

给 [DSH Go](https://github.com/ccch1mneyyy/dsh-Go) 的 Linux 环境开一条**真实 root** 通道的 Magisk / KernelSU / APatch 模块。

不改 APK、不改签名、不用 Xposed。容器本身仍然是 `proot` 的假 root，只有在命令前加 `dev` 时才真正以 uid 0 执行。

```
许可：GPL-3.0-or-later
支持：Magisk / KernelSU / APatch（同一套模块格式）
架构：arm64 / armv7（纯 shell，不依赖 ABI）
```

---

## 它解决什么问题

DSH Go 在手机上用一个 `proot` 容器跑 Ubuntu 环境，启动参数里带 `-0`：

```
libproot.so ... -0 --rootfs=<App私有目录>/files/runtime/rootfs ...
```

`-0` 是 proot 的 `--root-id`，只在内核调用层面**假装** uid 0。容器里 `id` 显示 `uid=0(root)`，但实际身份仍是应用自己：

| | 容器内（默认） | 真实情况 |
|---|---|---|
| `id` 输出 | `uid=0(root)` | 假象 |
| `/proc/self/status` 的 `Uid:` | `0 0 0 0`？不，是应用 uid | 真相 |
| `CapEff` | `0000000000000000` | 没有任何能力 |
| SELinux 域 | `u:r:untrusted_app_27:s0` | 应用域 |
| 能否 `ls /data/data` | 拒绝 | 被 SELinux 挡住 |

所以容器里既看不到 `/data`，也拿不到任何真实特权。

本模块在**容器外面**另起一个真正的 uid 0 进程，用 DSH Go 自己已经挂进容器的目录当信箱，让容器内的命令能递给它执行，再把结果取回来。

---

## 原理

DSH Go 启动容器时，启动参数里有这么一条 bind：

```
-b  <App私有目录>/files/runtime/rootfs/var/lib/dsh-app/shm:/dev/shm
```

于是宿主机和容器共享同一个物理目录，只是两个名字。本模块就是利用这个既有的门缝：

```
        容器内（应用 uid）                    容器外（uid 0）
   ┌──────────────────────────┐      ┌──────────────────────────┐
   │ dev / sudo / dshx        │      │ rootd.sh                 │
   │   ↓ 写 <id>.req           │      │   取走 → 执行 → 写回      │
   │ /dev/shm/rootq/          │◄────►│ <rootfs>/var/lib/…/rootq/│
   │   ↑ 读 <id>.out           │      │                          │
   └──────────────────────────┘      └──────────────────────────┘
                    ▲                            ▲
                    │                            │ heartbeat.sh 每 2 秒写时间戳
                    └──── 同一个物理目录 ─────────┘
```

- 客户端（`su-shim.sh`）**不执行任何东西**，它只写请求、等结果
- 服务端（`rootd.sh`）是唯一执行者，uid 0，SELinux 域 `u:r:ksu:s0` / `u:r:magisk:s0`
- 通信完全靠文件系统，不占端口、不建长连接、不需要 Xposed

### 三条独立的流

| 流 | 参与者 | 作用 |
|---|---|---|
| 指令流 | `su-shim.sh` ↔ `rootd.sh` | 塞请求、取结果 |
| 心跳流 | `heartbeat.sh` → 心跳文件 | 证明服务端还活着 |
| 启动流 | `service.sh` / `action.sh` → `repair.sh` | 装客户端、拉起服务端 |

**心跳为什么必须独立进程**：`rootd.sh` 是单线程，执行命令时会阻塞。如果把心跳写在它的主循环里，一条 `dev sleep 20` 就会让心跳停 20 秒，被客户端误判为「服务端已死」而拒绝后续调用。所以 `heartbeat.sh` 必须单独跑。

---

## 安装

### 面具里安装

下载 `dshgo-rootchan-<版本>.zip` → 面具 App → 模块 → 从本地安装 → 重启。

### 命令行安装

```bash
# Magisk
adb push dshgo-rootchan-v2.1.0.zip /data/local/tmp/
adb shell su -c "magisk --install-module /data/local/tmp/dshgo-rootchan-v2.1.0.zip"

# KernelSU / APatch
adb shell su -c "ksud module install /data/local/tmp/dshgo-rootchan-v2.1.0.zip"
```

装完如果不想重启，去面具里点本模块的「操作」按钮即可立即生效。

**前提**：DSH Go 已经安装并且**至少打开过一次**，让它把运行时（约 800 MB 的 rootfs）解压出来。否则客户端没有地方可放。

---

## 使用

在 DSH 的对话里让它执行，或者用它自带的终端：

```bash
dev id                        # 在手机上以 root 执行
dev pm list packages -3       # 列第三方应用
dev settings put global airplane_mode_on 1
dev cat /data/data/<包名>/databases/x.db
dev ls /data/adb
```

`dev`、`sudo`、`dshx on-device` 三个等价。

### 双环境路由

| 命令 | 在哪执行 |
|---|---|
| 不加前缀：`npm i`、`git status`、`python3 x.py` | 容器（Ubuntu） |
| 加 `dev`：`dev pm`、`dev /data/...` | 手机本体（root） |

```bash
dshx where                    # 看两边状态
dshx doctor                   # 出问题先跑这个，一次查完并给修法
dshx cp-to-device    <容器路径> <设备路径>
dshx cp-to-container <设备路径> <容器路径>
```

### 路径对照

| 容器内 | 手机上 | 同一份？ |
|---|---|---|
| `/sdcard` | `/storage/emulated/0` | 是，共享读写 |
| `/system` `/apex` | 同左 | 是，共享只读 |
| `/dev` `/proc` `/sys` | 同左 | 是 |
| `/root` `/usr` `/bin` `/tmp` | —— | 不是，Ubuntu 自己的 |
| **不存在** | `/data` | —— |
| `/root/workspace` | `$DSH_GO_RUNTIME_ROOT/root/workspace` | 是 |

### 五个坑

1. 容器里 `ls /data` 失败 **≠** 设备没有 `/data`。用 `dev ls /data`。
2. 容器里敲 `su -c` 会**假成功**：命中 Ubuntu 自带的 util-linux `su`，被拦截后仍打印 `uid=0(root)`，实际什么都没发生。只用 `dev`。
3. 两边都有 `sh`/`ls`，但不是同一个程序：不加前缀是 coreutils，加 `dev` 是 toybox，参数支持不同。
4. 改 `/sdcard` 上的文件两边都生效。
5. 与设备上的 App 交换文件用 `dshx cp-to-*`，别手写 `cp`。

### 验证是真 root

```bash
dev grep -E '^(Uid|CapEff|TracerPid)' /proc/self/status
```

三条同时成立才算真：`Uid:` 全是 0、`CapEff:` 不是一串 0、`TracerPid:` 是 `0`。

---

## 目录结构

```
module.prop          模块身份
customize.sh         安装时：清旧版残留、检测 DSH Go、立即启用
service.sh           开机：等运行时出现 → repair
action.sh            「操作」按钮：立即修复并打印状态
repair.sh            幂等修复：装客户端 + 起服务端（被上面三个调用）
rootd.sh             服务端：uid 0，读信箱执行命令
heartbeat.sh         心跳：独立进程，每 2 秒原子写时间戳
su-shim.sh           客户端：被复制成容器内的 su / sudo / dev
dshx.sh              路由与诊断（where / doctor / cp-to-*）
uninstall.sh         卸载清理
skill/SKILL.md       给 DSH 的 AI 读的环境规则（什么时候该加 dev）
```

---

## 构建

```bash
./build.sh          # 需要 zip
```

产物 `dshgo-rootchan-<version>.zip`。也可以直接用 GitHub Actions 的 artifact（见 `.github/workflows/build.yml`）。

---

## 卸载

面具里删除本模块 → `uninstall.sh` 会：

- 停掉 `rootd.sh` 和 `heartbeat.sh`
- 删掉容器内的 `su` / `sudo` / `dev` / `dshx` 和规则卡
- 删掉信箱目录
- 清掉早期散装脚本版的残留

DSH Go 本身的文件和设置一律不碰。

---

## 已知限制

| 限制 | 说明 |
|---|---|
| **没有看门狗** | 服务端意外退出不会自动复活。点模块的「操作」按钮恢复。手机重启会自动恢复 |
| 依赖 `/dev/shm` 这个 bind | 如果 DSH Go 把引擎切到 **Direct** 模式，容器里没有 `/dev/shm`，通道失效。用 proot 或 tawcroot |
| App 升级运行时会冲掉客户端 | rootfs 被整个替换，四个命令消失。点「操作」按钮恢复 |
| 只支持 arm64 / armv7 | 模块本身是纯 shell，不挑 ABI；但 DSH Go 目前只出 arm64 包 |
| 依赖 KernelSU/Magisk 的 `su` | 没有 root 管理器的环境不适用 |

### 想恢复自动复活

仓库历史里的 `v2.0.6` 带看门狗（常驻每 60 秒检查心跳）。把 `watchdog.sh` 和 `service.sh` 末尾那段加回来即可。

---

## 安全提示

装上之后，**容器里任何能执行代码的东西**（AI、插件、被提示词注入的指令）都能拿到设备最高权限，**而且不会弹确认框**——DSH Go 原本设计的「每条特权命令都要原生二次确认」被绕过了。

这是功能本身的代价。不需要的时候就把模块停用或删掉。

---

## 背景

DSH Go 上游对 root 的态度可以参考这几个 issue：

- [#365](https://github.com/ccch1mneyyy/dsh-Go/issues/365) chroot 引擎（root 只做 mount + setpriv 降权）
- [#470](https://github.com/ccch1mneyyy/dsh-Go/issues/470) 以 root 身份启动本机运行时

本模块走的是另一条路：**完全不碰 DSH Go 的启动路径**，因此不触发 `DshProcess.signalOwned()` 那套按 uid 判定的所有权与停止机制（把引擎整个跑成 root 会打断它，App 就停不掉引擎）。

---

## 许可

```
Copyright (C) 2026 Vladivostok1017

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
```

完整条款见 [LICENSE](LICENSE)。SPDX: `GPL-3.0-or-later`。

上游项目 [dsh-Go](https://github.com/ccch1mneyyy/dsh-Go) 由其作者按自己的许可发布，本模块不包含其任何代码。
