#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vladivostok1017
# 打包成面具可刷入的 zip。需要 zip（GitHub Actions 的 ubuntu runner 自带）。
set -eu
cd "$(dirname "$0")"

VER=$(sed -n 's/^version=//p' module.prop)
NAME=$(sed -n 's/^id=//p' module.prop)
OUT="${NAME}-${VER}.zip"

# 只打包模块真正需要的文件：module.prop 必须在 zip 根目录
FILES="module.prop customize.sh service.sh action.sh repair.sh rootd.sh heartbeat.sh su-shim.sh dshx.sh uninstall.sh skill"

rm -f "$OUT"
# shellcheck disable=SC2086
zip -r -q "$OUT" $FILES

echo "built: $OUT"
unzip -l "$OUT"
