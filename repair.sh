#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vladivostok1017
# 幂等：把客户端装进 DSH Go 的 rootfs，并保证管理员在跑。
# 开机、看门狗、模块「操作」按钮都调它。
MODDIR="${MODDIR:-$(dirname "$0")}"

ROOTFS=""
for d in /data/user/*/*/files/runtime/rootfs /data/data/*/files/runtime/rootfs; do
  [ -d "$d" ] && { ROOTFS="$d"; break; }
done
[ -n "$ROOTFS" ] || exit 0          # 运行时还没装好，下次再来

SHM="$ROOTFS/var/lib/dsh-app/shm"
Q="$SHM/rootq"
BIN="$ROOTFS/usr/local/bin"
SKILLDIR="$ROOTFS/root/.dsh/skills/android-dual-env"

mkdir -p "$SHM" "$Q" "$BIN" "$SKILLDIR"
chmod 0777 "$SHM" "$Q" 2>/dev/null

# 客户端：三份独立副本，不依赖符号链接
cp -f "$MODDIR/su-shim.sh" "$BIN/su";   chmod 0755 "$BIN/su"
cp -f "$MODDIR/su-shim.sh" "$BIN/sudo"; chmod 0755 "$BIN/sudo"
cp -f "$MODDIR/su-shim.sh" "$BIN/dev";  chmod 0755 "$BIN/dev"
cp -f "$MODDIR/dshx.sh"    "$BIN/dshx"; chmod 0755 "$BIN/dshx"
cp -f "$MODDIR/skill/SKILL.md" "$SKILLDIR/SKILL.md"; chmod 0644 "$SKILLDIR/SKILL.md"

# 当场自检，缺什么直接报，不留到用的时候
miss=""
for f in su sudo dev dshx; do [ -e "$BIN/$f" ] || miss="$miss $f"; done
[ -f "$SKILLDIR/SKILL.md" ] || miss="$miss SKILL.md"
if [ -n "$miss" ]; then
  echo "repair: 没装进去，缺:$miss" >&2
  ls -la "$BIN" >&2 2>&1
  exit 1
fi

# 健康 = pid 活着 且 心跳是有效时间戳且没过期。
# 心跳由独立的 heartbeat.sh 每 2 秒更新，所以 30 秒没动才算真死。
healthy=0
if [ -f "$Q/rootd.pid" ]; then
  P=$(cat "$Q/rootd.pid" 2>/dev/null)
  if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then
    ht=$(cat "$Q/heartbeat" 2>/dev/null | tr -dc '0-9')
    now=$(date +%s 2>/dev/null || echo 0)
    if [ -n "$ht" ] && [ "$now" -gt 0 ] && [ $((now - ht)) -le 30 ]; then
      healthy=1
    fi
  fi
fi
[ "$healthy" = "1" ] && exit 0

# 不健康：清掉所有可能的管理员与心跳进程（含早期散装版留下的老进程），
# 避免两个管理员抢同一个信箱导致结果错乱。
for p in $(pgrep -f "rootd.sh" 2>/dev/null); do
  cl=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
  case "$cl" in *dsh*rootchan*) kill "$p" 2>/dev/null ;; esac
done
for p in $(pgrep -f "heartbeat.sh" 2>/dev/null); do
  cl=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
  case "$cl" in *dsh*rootchan*) kill "$p" 2>/dev/null ;; esac
done
sleep 0.5

rm -f "$Q"/*.req "$Q"/*.out "$Q"/*.tmp "$Q/rootd.pid" "$Q/heartbeat" 2>/dev/null

chmod 0755 "$MODDIR/rootd.sh" "$MODDIR/heartbeat.sh" 2>/dev/null
if command -v setsid >/dev/null 2>&1; then
  MODDIR="$MODDIR" setsid nohup sh "$MODDIR/rootd.sh" >/dev/null 2>&1 </dev/null &
else
  MODDIR="$MODDIR" nohup sh "$MODDIR/rootd.sh" >/dev/null 2>&1 </dev/null &
fi

i=0
while [ $i -lt 25 ]; do
  [ -s "$Q/rootd.pid" ] && kill -0 "$(cat "$Q/rootd.pid")" 2>/dev/null && exit 0
  i=$((i + 1))
  sleep 0.2
done
exit 1
