#!/usr/bin/env bash
#
# build.sh · 鸿蒙端命令行构建（等价于 DevEco Studio 的 Build Hap）
#
# ────────────────── 为什么需要这个脚本 ──────────────────
# 1) 本机**没有** `hvigorw` 包装器（DevEco 6.1 的工程模板没生成它），
#    所以直接用 DevEco 自带的 hvigor 入口：
#      <DevEco>/tools/hvigor/hvigor/bin/hvigor.js
# 2) hvigor 需要一个「用户目录」放工程缓存与依赖软链接，通过 **HVIGOR_USER_HOME** 指定
#    （★ 不是 HVIGOR_HOME —— 那个变量 hvigor 根本不读，设了也没用）。
#    默认会落到 `~/.hvigor`；若那里的 workspace 是坏的（软链接被 IDE 占住、realpath 失败），
#    会报 `00308003 ENOENT ... workspace/node_modules/@ohos/hvigor/bin/hvigor.js`，
#    此时删掉那个 workspace 目录让它重建即可。
# 3) `PackageHap` 要调 `java`，而 Windows 上 PATH 里通常没有 JDK ——
#    必须把 DevEco 自带的 JBR 加进 PATH，否则报 `spawn java ENOENT`。
# 4) 在受限沙箱里跑会报 `es2abc ... spawn EPERM`（子进程管道被 ACL 拦），
#    这不是代码问题，换成本脚本这种不受限的方式执行即可。
#
# 用法：
#   bash harmony/scripts/build.sh              # 默认构建 debug HAP
#   bash harmony/scripts/build.sh clean        # 只清理产物
#
# 产物：harmony/entry/build/default/outputs/default/entry-default-unsigned.hap

set -uo pipefail

# ── 路径（按本机实际安装位置，换机器改这两行）──
DEVECO_HOME="${DEVECO_HOME:-/e/HarmonyOS/DevEco Studio}"
HVIGOR_USER_HOME_DIR="${HVIGOR_USER_HOME_DIR:-/e/hvigor-home-mindscope}"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export DEVECO_SDK_HOME="${DEVECO_HOME}/sdk"
export HVIGOR_USER_HOME="${HVIGOR_USER_HOME_DIR}"
export PATH="${DEVECO_HOME}/jbr/bin:${PATH}"

HVIGOR_JS="${DEVECO_HOME}/tools/hvigor/hvigor/bin/hvigor.js"
LOG="${PROJECT_DIR}/_build.log"

if [ ! -f "${HVIGOR_JS}" ]; then
  echo "找不到 hvigor 入口：${HVIGOR_JS}" >&2
  echo "请检查 DEVECO_HOME 是否指向 DevEco Studio 安装目录。" >&2
  exit 2
fi

cd "${PROJECT_DIR}" || exit 2

if [ "${1:-assembleHap}" = "clean" ]; then
  rm -rf entry/build build .hvigor
  echo "已清理构建产物"
  exit 0
fi

node "${HVIGOR_JS}" \
  --mode module -p product=default -p module=entry@default \
  assembleHap --no-daemon > "${LOG}" 2>&1
STATUS=$?

# 只打印关键行，避免刷屏；完整日志留在 _build.log
grep -E "ERROR|COMPILE RESULT|BUILD (FAILED|SUCCESSFUL)" "${LOG}" | tail -30

if [ ${STATUS} -ne 0 ]; then
  echo "---- 构建失败，完整日志：${LOG} ----"
  exit ${STATUS}
fi

echo "构建成功：entry/build/default/outputs/default/entry-default-unsigned.hap"
exit 0
