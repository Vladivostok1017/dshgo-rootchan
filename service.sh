#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vladivostok1017
# 开机 late_start 阶段由 magiskd 调用。父进程是 magiskd，不会被后台清理。
#
# 说明：本模块**不带看门狗**。管理员（rootd）意外死掉时不会自动复活，
# 需要去面具里点本模块的「操作」按钮。手机重启仍会自动恢复（就是这里）。
MODDIR="${MODDIR:-$(dirname "$0")}"

# 等 DSH Go 的运行时出现（最多 4 分钟），然后装客户端 + 起管理员
i=0
while [ $i -lt 120 ]; do
  for d in /data/user/*/*/files/runtime/rootfs /data/data/*/files/runtime/rootfs; do
    if [ -d "$d" ]; then
      MODDIR="$MODDIR" sh "$MODDIR/repair.sh" >> "$MODDIR/last.log" 2>&1
      exit 0
    fi
  done
  i=$((i + 1))
  sleep 2
done
