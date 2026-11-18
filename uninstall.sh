#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vladivostok1017
# 模块被删除/停用时由面具调用：停掉常驻进程，把 DSH Go 恢复原样。
MODDIR="${MODDIR:-$(dirname "$0")}"

pkill -f "dshgo-rootchan/watchdog.sh" 2>/dev/null
pkill -f "dshgo-rootchan/rootd.sh" 2>/dev/null
pkill -f "rootchan/heartbeat.sh" 2>/dev/null

for r in /data/user/*/*/files/runtime/rootfs /data/data/*/files/runtime/rootfs; do
  [ -d "$r" ] || continue
  Q="$r/var/lib/dsh-app/shm/rootq"
  [ -f "$Q/rootd.pid" ] && kill "$(cat "$Q/rootd.pid")" 2>/dev/null
  rm -rf "$Q"
  B="$r/usr/local/bin"
  rm -f "$B/su" "$B/sudo" "$B/dev" "$B/dshx"
  rm -rf "$r/root/.dsh/skills/android-dual-env"
done

# 早期散装脚本版残留
rm -rf /data/adb/dsh-rootchan
rm -f /data/adb/service.d/dsh-rootchan.sh
