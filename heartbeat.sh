#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vladivostok1017
# 心跳：独立进程，每 2 秒写一次时间戳。
#
# 三个要点：
# 1. 必须和 rootd 主循环分开——否则 rootd 执行长命令时主循环阻塞，心跳会停，
#    被容器里的 shim 误判成「管理员死了」。
# 2. 必须原子写入（写临时文件再 mv）。直接 `date > file` 会先截断再写，
#    容器侧恰好在这一瞬间读就会读到空文件，同样被误判成死亡。
# 3. 写出来的文件必须对容器可读。root / KernelSU 的 su 的 umask 可能是 077，
#    不显式放宽的话文件是 600，容器里（应用 uid）读不到，同样误判成死亡。
#    umask 和 chmod 两道都做，因为 mv 会保留临时文件的权限位。
umask 022
Q="${ROOTD_Q:-}"
if [ -z "$Q" ]; then
  for base in /data/user/*/*/files/runtime/rootfs /data/data/*/files/runtime/rootfs; do
    [ -d "$base" ] || continue
    Q="$base/var/lib/dsh-app/shm/rootq"
    break
  done
fi
[ -n "${Q:-}" ] || exit 1

HB="$Q/heartbeat"
TMP="$HB.tmp"

while :; do
  t=$(date +%s 2>/dev/null)
  if [ -n "$t" ]; then
    if printf '%s\n' "$t" > "$TMP" 2>/dev/null; then
      chmod 0644 "$TMP" 2>/dev/null
      mv -f "$TMP" "$HB" 2>/dev/null
      chmod 0644 "$HB" 2>/dev/null
    fi
  fi
  sleep 2
done
