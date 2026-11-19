#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vladivostok1017
set -u
SHIM="${DSHX_SHIM:-/usr/local/bin/sudo}"
Q="${ROOTD_Q:-/dev/shm/rootq}"
ROOT_PHYS="${DSH_GO_RUNTIME_ROOT:-}"

usage() {
  cat <<'EOS'
dshx — 容器 / 设备 路由

  dshx where                              看两边状态
  dshx doctor                             出问题先跑这个，一次查完并给修法
  dshx on-device <命令...>                在手机上以 root 执行（= dev）
  dshx in-container <命令...>             强制在容器里执行
  dshx cp-to-device    <容器路径> <设备路径>
  dshx cp-to-container <设备路径> <容器路径>
EOS
}

to_phys() {
  p="$1"
  case "$p" in
    /sdcard*|/storage/*|/system*|/apex*|/dev/*|/proc/*|/sys/*|/data/*) printf '%s\n' "$p" ;;
    /*)
      [ -n "$ROOT_PHYS" ] || { echo "dshx: 没有 DSH_GO_RUNTIME_ROOT，换算不了 $p" >&2; return 1; }
      printf '%s%s\n' "$ROOT_PHYS" "$p" ;;
    *) echo "dshx: 要绝对路径，收到 $p" >&2; return 1 ;;
  esac
}

hb_age() {
  local ht now n
  now=$(date +%s 2>/dev/null || echo 0)
  ht=""
  n=0
  while [ $n -lt 6 ]; do
    ht=$(tr -dc '0-9' < "$Q/heartbeat" 2>/dev/null)
    [ -n "$ht" ] && break
    n=$((n + 1))
    sleep 0.1
  done
  if [ -n "$ht" ] && [ "$now" -gt 0 ]; then echo $((now - ht)); else echo 99999; fi
}

doctor() {
  echo "=== 1. 你在哪 ==="
  echo "  容器 uid=$(id -u)  cwd=$(pwd)"
  echo "  rootfs 物理路径：${ROOT_PHYS:-<App 没提供这个变量>}"
  echo
  echo "=== 2. 信箱在不在 ==="
  if [ -d /dev/shm ]; then echo "  ✓ /dev/shm 在"; else echo "  ✗ 容器里没有 /dev/shm → 引擎可能是 Direct，切回 proot"; fi
  if [ -d "$Q" ]; then echo "  ✓ $Q 在"; else echo "  ✗ $Q 不在 → 没装，或 App 升级时把运行时换了"; fi
  echo
  echo "=== 3. 管理员活着吗 ==="
  if [ -f "$Q/rootd.pid" ]; then echo "  pid=$(cat "$Q/rootd.pid" 2>/dev/null)"; else echo "  ✗ 没有 pid 文件"; fi
  age=$(hb_age)
  if [ "$age" = "99999" ]; then echo "  ✗ 没有心跳文件"; else echo "  心跳：${age} 秒前（超过 8 秒算死）"; fi
  echo
  echo "=== 4. 客户端装对了吗 ==="
  for f in /usr/local/bin/su /usr/local/bin/sudo /usr/local/bin/dev /usr/local/bin/dshx; do
    if [ -e "$f" ]; then echo "  ✓ $f"
    elif [ -L "$f" ]; then echo "  △ $f 是符号链接，但指向的目标不存在（这就是 dev 找不到的原因）"
    else echo "  ✗ 缺 $f"; fi
  done
  echo "  PATH 里第一个 sudo → $(command -v sudo 2>/dev/null)"
  echo "  PATH 里第一个 dev  → $(command -v dev 2>/dev/null)"
  echo "  PATH = $PATH"
  echo
  echo "=== 5. 设备那边 ==="
  if [ -x "$SHIM" ]; then
    if out=$("$SHIM" 'id -u' 2>&1); then echo "  ✓ 通，设备侧 uid=$out"; else echo "  ✗ 不通：$out"; fi
  else
    echo "  ✗ $SHIM 不存在"
  fi
  echo
  echo "=== 结论 ==="
  if [ "$age" != "99999" ] && [ "$age" -le 8 ]; then
    echo "  通道正常。要是某条命令还是失败，把那条命令 + 这份输出一起发出来。"
    return
  fi
  echo "  通道不健康。去面具里点本模块的「操作」按钮，或重启一次。"
}

case "${1:-}" in
  where)
    echo "== 容器（你在这里）=="
    echo "  uid=$(id -u)  cwd=$(pwd)"
    echo "  rootfs=${ROOT_PHYS:-<未提供>}"
    echo "  提醒：这里看不见 /data；/sdcard /system 是共享的"
    echo
    echo "== 设备（手机本体）=="
    if [ -x "$SHIM" ] && "$SHIM" 'echo probe' >/dev/null 2>&1; then
      "$SHIM" 'echo "  ✓ 可用"; echo "  uid=$(id -u)"; echo "  CapEff=$(grep CapEff /proc/self/status | cut -f2)"'
    else
      echo "  ✗ 不可用 → 跑 dshx doctor"
    fi
    ;;
  doctor) doctor ;;
  on-device) shift; [ $# -gt 0 ] || { usage; exit 64; }; exec "$SHIM" "$*" ;;
  in-container) shift; [ $# -gt 0 ] || { usage; exit 64; }; exec /bin/bash -lc "$*" ;;
  cp-to-device)
    shift; [ $# -ge 2 ] || { usage; exit 64; }
    phys=$(to_phys "$1") || exit 1
    "$SHIM" "if [ ! -e '$phys' ]; then echo '源不存在: $phys' >&2; exit 1; fi
mkdir -p '$(dirname "$2")' && cp -a '$phys' '$2' && echo 'ok -> $2'" ;;
  cp-to-container)
    shift; [ $# -ge 2 ] || { usage; exit 64; }
    phys=$(to_phys "$2") || exit 1
    # 复制是 root 执行的，不处理属主的话拉进来就是 root 拥有，
    # 容器里以应用 uid 运行的 DSH 会读不了 —— 和心跳那个 bug 同一个成因。
    me=$(id -u 2>/dev/null || echo 0)
    "$SHIM" "if [ ! -e '$1' ]; then echo '源不存在: $1' >&2; exit 1; fi
mkdir -p '$(dirname "$phys")' || exit 1
cp -a '$1' '$phys' || exit 1
chown -R $me:$me '$phys' 2>/dev/null
chmod -R a+rX '$phys' 2>/dev/null
echo 'ok -> $phys'" ;;
  ""|-h|--help|help) usage ;;
  *) echo "dshx: 不认识的子命令 $1" >&2; usage; exit 64 ;;
esac
