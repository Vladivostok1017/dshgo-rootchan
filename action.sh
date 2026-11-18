#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vladivostok1017
# 面具模块详情页的「操作」按钮：立即修复并启动，顺便打印状态。
#
# 本模块没有看门狗，所以这个按钮是「管理员死了」之后唯一的手动恢复入口。
MODDIR="${MODDIR:-$(dirname "$0")}"

echo "=== DSH Go Root Channel ==="

ROOTFS=""
for d in /data/user/*/*/files/runtime/rootfs /data/data/*/files/runtime/rootfs; do
  [ -d "$d" ] && { ROOTFS="$d"; break; }
done

if [ -z "$ROOTFS" ]; then
  echo "没找到 DSH Go 运行时：先打开 DSH Go 让它把运行时装好。"
  exit 0
fi

echo "运行时：$ROOTFS"

if MODDIR="$MODDIR" sh "$MODDIR/repair.sh"; then
  echo "管理员：已启动（pid $(cat "$ROOTFS/var/lib/dsh-app/shm/rootq/rootd.pid" 2>/dev/null)）"
  echo "心跳：  $(cat "$ROOTFS/var/lib/dsh-app/shm/rootq/heartbeat" 2>/dev/null)"
else
  echo "管理员：启动失败"
  echo "详见 $ROOTFS/var/lib/dsh-app/shm/rootq/rootd.log"
fi

echo ""
echo "去 DSH 的环境里敲： dshx doctor"
