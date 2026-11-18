#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vladivostok1017
# 安装时执行（由面具调用，此时已是 root）。
#
# 重要：这里不碰 DSH Go 的 rootfs。
# 早期版本在这里 `rm` 掉 su/sudo/dev/dshx，以为 repair 会补回来——但 repair
# 只在开机、看门狗超时、点「操作」时跑，于是「升级模块」等于「四个命令消失」。
# repair.sh 本来就用 cp -f 覆盖，不需要先删。

ui_print "- DSH Go Root Channel"

# 清掉早期「散装脚本版」的残留（在模块目录之外，必须清）
if [ -d /data/adb/dsh-rootchan ]; then
  ui_print "- 清理旧脚本版残留 /data/adb/dsh-rootchan"
  rm -rf /data/adb/dsh-rootchan
fi
if [ -f /data/adb/service.d/dsh-rootchan.sh ]; then
  ui_print "- 清理旧脚本版开机项"
  rm -f /data/adb/service.d/dsh-rootchan.sh
fi

found=0
for d in /data/user/*/*/files/runtime/rootfs /data/data/*/files/runtime/rootfs; do
  [ -d "$d" ] && { found=1; break; }
done

if [ "$found" = "1" ]; then
  ui_print "- 已检测到 DSH Go 运行时"
else
  ui_print "- 暂未检测到 DSH Go 运行时（还没装或没打开过）"
  ui_print "  装好后开机会自动接管，也可以点「操作」按钮立即启用"
fi

# 装完立刻启用：把客户端放进 rootfs 并确保管理员在跑。
# 不依赖开机，避免「装完还得等重启」。
if [ "$found" = "1" ]; then
  M="${MODPATH:-}"
  [ -n "$M" ] || M=/data/adb/modules_update/dshgo-rootchan
  [ -d "$M" ] || M=/data/adb/modules/dshgo-rootchan
  if [ -f "$M/repair.sh" ]; then
    ui_print "- 正在启用…"
    if MODDIR="$M" sh "$M/repair.sh"; then
      ui_print "- 已启用。去 DSH 里敲：dshx doctor"
    else
      ui_print "- 启用失败，开机时会自动重试，也可以点「操作」按钮"
    fi
  fi
fi
