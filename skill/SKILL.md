---
name: android-dual-env
description: 在 DSH Go 的 Linux 容器与真实 Android 设备之间选择正确的执行环境。涉及系统设置、其他 App 数据、/data、pm/am/settings、开机重启、安装卸载这类「碰手机本体」的任务，或需要判断路径属于容器还是设备时，用这个技能。
---

# Android 双环境：容器 vs 设备

默认在容器里。**要碰手机本体 → 命令前加 `dev`。**

| | 容器 | 设备 |
|---|---|---|
| 怎么进 | 什么都不加 | 前面加 `dev` |
| 身份 | 应用 uid，CapEff 为 0 | 真 root，CapEff 非 0 |
| 能看 `/data` | **看不见** | 能看 |

判断口诀：命令里出现 `pm` / `am` / `settings` / `/data` / 对其他 App 的操作 → 加 `dev`。

## 命令

```bash
dev <命令>            # 设备上以 root 执行
dshx where            # 两边状态
dshx doctor           # 出问题先跑这个
dshx cp-to-device  <容器路径> <设备路径>
dshx cp-to-container <设备路径> <容器路径>
```

`dev` 和 `dshx on-device` 等价；前者找不到时用后者。

## 路径对照

| 容器 | 设备 | 同一份？ |
|---|---|---|
| `/sdcard` | `/storage/emulated/0` | 是，读写 |
| `/system` `/apex` | 同左 | 是，只读 |
| `/dev` `/proc` `/sys` | 同左 | 是 |
| `/root` `/usr` `/bin` `/tmp` | —— | 不是，Ubuntu 自己的 |
| **不存在** | `/data` | —— |
| `/root/workspace` | `$DSH_GO_RUNTIME_ROOT/root/workspace` | 是 |

## 五个坑

1. 容器里 `ls /data` 失败 ≠ 设备没有 `/data`。用 `dev ls /data`。
2. 容器里敲 `su -c` 会假成功（命中 Ubuntu 的 util-linux su，打印 uid=0 但什么也没发生）。只用 `dev`。
3. 两边都有 `sh`/`ls` 但不是同一个程序：不加 `dev` 是 coreutils，加 `dev` 是 toybox，参数支持不同。
4. 改 `/sdcard` 上的文件两边都生效。
5. 与设备上的 App 交换文件用 `dshx cp-to-*`，别手写 `cp`。

## 出错时

**不要猜，先跑 `dshx doctor`。** 它会说清：信箱在不在、管理员活着没、客户端装对没、设备侧通不通，并给修法。

需要人在手机侧动手时，提示去面具里点本模块的「操作」按钮。

## 验证真 root

```bash
dev grep -E '^(Uid|CapEff|TracerPid)' /proc/self/status
```

`Uid` 全 0 + `CapEff` 非 0 + `TracerPid` 为 0，三条同时成立。
