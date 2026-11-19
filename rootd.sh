#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vladivostok1017
# 门外的管理员：uid 0。靠 /dev/shm 里的小信箱跟容器对话。
# 心跳由独立的 heartbeat.sh 维护，这里只专心处理命令。
Q="${ROOTD_Q:-}"
if [ -z "$Q" ]; then
  for base in /data/user/*/*/files/runtime/rootfs /data/data/*/files/runtime/rootfs; do
    [ -d "$base" ] || continue
    Q="$base/var/lib/dsh-app/shm/rootq"
    break
  done
fi
[ -n "${Q:-}" ] || exit 1

mkdir -p "$Q" 2>/dev/null
chmod 0777 "$Q" 2>/dev/null
export PATH=/product/bin:/system/bin:/system/xbin:/sbin:/vendor/bin
# root / su 的 umask 可能是 077，会让 pid 和日志变成 600，
# 容器里的 dshx doctor 就读不到它们。显式放宽。
umask 022

PIDFILE="$Q/rootd.pid"
HB="$Q/heartbeat"
LOG="$Q/rootd.log"

echo $$ > "$PIDFILE"
chmod 0644 "$PIDFILE" 2>/dev/null
exec 2>>"$LOG"
chmod 0644 "$LOG" 2>/dev/null
echo "[rootd] up pid=$$ uid=$(id -u) domain=$(cat /proc/self/attr/current 2>/dev/null)" >>"$LOG"

# 清掉启动前留下的垃圾：没人取的旧结果、没处理完的请求
rm -f "$Q"/*.req "$Q"/*.req.tmp "$Q"/*.out "$Q"/*.out.tmp 2>/dev/null

# 心跳进程：先清掉上一个，再起新的
for p in $(pgrep -f "heartbeat.sh" 2>/dev/null); do
  cl=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
  case "$cl" in *rootchan*) kill "$p" 2>/dev/null ;; esac
done
HBSH="$(dirname "$0")/heartbeat.sh"
if [ -f "$HBSH" ]; then
  ROOTD_Q="$Q" setsid nohup sh "$HBSH" >/dev/null 2>&1 </dev/null &
fi
date +%s > "$HB.tmp" 2>/dev/null && mv -f "$HB.tmp" "$HB" 2>/dev/null

while :; do
  for req in "$Q"/*.req; do
    [ -e "$req" ] || continue
    base="${req##*/}"
    id="${base%.req}"
    cmd=$(cat "$req" 2>/dev/null) || cmd=""
    rm -f "$req" 2>/dev/null
    [ -n "$cmd" ] || continue

    if [ "$cmd" = "__rootd_stop__" ]; then
      rm -f "$PIDFILE"
      exit 0
    fi

    out="$Q/$id.out"
    tmp="$out.tmp"
    if command -v timeout >/dev/null 2>&1; then
      timeout 900 /system/bin/sh -c "$cmd" >"$tmp" 2>&1
      code=$?
    else
      /system/bin/sh -c "$cmd" >"$tmp" 2>&1
      code=$?
    fi
    printf '\n[exit] %s\n' "$code" >>"$tmp"
    chmod 0644 "$tmp" 2>/dev/null
    mv -f "$tmp" "$out"
  done
  sleep 0.2
done
