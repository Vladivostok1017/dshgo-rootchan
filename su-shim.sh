#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vladivostok1017
# 容器里的客户端。不自己执行，把命令塞进信箱，等结果。
set -u
Q="${ROOTD_Q:-/dev/shm/rootq}"
hb="$Q/heartbeat"

fail() { printf '%s\n' "$*" >&2; exit 126; }

reason() {
  if [ ! -d /dev/shm ]; then
    printf 'root 通道用不了：容器里没有 /dev/shm。\n这通常是引擎被切成了 Direct，切回 proot 就好。\n'
  elif [ ! -d "$Q" ]; then
    printf 'root 通道没装好（缺 %s）。\n去面具里点本模块的「操作」按钮，或重启一次。\n' "$Q"
  else
    printf '管理员没在跑（心跳停了）。\n去面具里点本模块的「操作」按钮，或重启一次。\n'
  fi
}

[ -d "$Q" ] || { reason; exit 126; }

cmd=""
while [ $# -gt 0 ]; do
  case "$1" in
    -c) shift; [ $# -gt 0 ] || fail "su -c 后面要跟命令"; cmd="$1"; shift ;;
    -s|--shell) shift; if [ $# -gt 0 ]; then cmd="$1"; shift; fi ;;
    --) shift; cmd="$*"; break ;;
    -u|-g) shift; shift ;;
    -n|-E|-H|-k|-S|-P|-A|-b) shift ;;
    --login) shift ;;
    -*) shift ;;
    root|-0|0) shift ;;
    *) cmd="${cmd:+$cmd }$1"; shift ;;
  esac
done
[ -n "$cmd" ] || fail "没有给命令"

# 读心跳。读到空文件时重试几次再判死，避开写入瞬间的竞态。
hb_age() {
  local ht now n
  now=$(date +%s 2>/dev/null || echo 0)
  ht=""
  n=0
  while [ $n -lt 6 ]; do
    ht=$(tr -dc '0-9' < "$hb" 2>/dev/null)
    [ -n "$ht" ] && break
    n=$((n + 1))
    sleep 0.1
  done
  if [ -n "$ht" ] && [ "$now" -gt 0 ]; then echo $((now - ht)); else echo 99999; fi
}

# 心跳每 2 秒更新一次，20 秒没动才算真死。
# 放宽到这个量级是为了不把「管理员正在执行上一条慢命令」误判成死亡。
age=$(hb_age)
[ "$age" -gt 20 ] && fail "$(reason)"

stamp=$(date +%s%N 2>/dev/null || echo 0)
id="$$-$stamp-${RANDOM:-0}"
req="$Q/$id.req"; tmp="$req.tmp"; out="$Q/$id.out"
printf '%s\n' "$cmd" > "$tmp" 2>/dev/null || fail "写不进 $Q"
mv -f "$tmp" "$req" 2>/dev/null || fail "排队失败（$Q）"

tries=0
while [ ! -f "$out" ]; do
  tries=$((tries + 1))
  [ "$tries" -gt 3000 ] && fail "命令 300 秒没回来。跑 dshx doctor 看看。"

  # 每 5 秒复核一次心跳，但只在明显停了很久时放弃，避免误杀慢命令。
  if [ $((tries % 50)) -eq 0 ]; then
    a=$(hb_age)
    if [ "$a" -gt 120 ]; then
      rm -f "$req" 2>/dev/null
      fail "管理员中途没了（心跳 ${a} 秒没动）。去面具点本模块的「操作」。"
    fi
  fi
  sleep 0.1
done

cat "$out"
code=$(sed -n 's/^\[exit\] \([0-9][0-9]*\)$/\1/p' "$out" 2>/dev/null | tail -n 1)
rm -f "$out" 2>/dev/null
exit "${code:-1}"
