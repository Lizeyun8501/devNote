#!/usr/bin/env bash
###############################################################################
# install_targets.sh — 安装 DevNote FFI 跨编译所需的全部 Rust 目标
#
# 用法:
#   ./install_targets.sh
#
# 说明:
#   - 自动列出所有需要的 cross-compilation 目标
#   - 执行 rustup target add 安装每个目标
#   - 标注需要额外工具链的目标 (Android NDK, iOS SDK 等)
###############################################################################
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# 需要安装的目标列表
# ─────────────────────────────────────────────────────────────────────────────
TARGETS=(
  "x86_64-unknown-linux-gnu"
  "x86_64-apple-darwin"
  "aarch64-apple-darwin"
  "x86_64-pc-windows-gnu"
  "aarch64-linux-android"
  "aarch64-apple-ios"
)

# ─────────────────────────────────────────────────────────────────────────────
# 目标 → 平台/额外依赖 映射 (用于提示)
# ─────────────────────────────────────────────────────────────────────────────
declare -A TARGET_NOTES=(
  [x86_64-unknown-linux-gnu]="Linux x86_64 — 通常无需额外工具链 (系统需安装 gcc/g++)"
  [x86_64-apple-darwin]="macOS x86_64 — 需要 macOS + Xcode Command Line Tools"
  [aarch64-apple-darwin]="macOS Apple Silicon — 需要 macOS + Xcode Command Line Tools"
  [x86_64-pc-windows-gnu]="Windows x86_64 (MinGW) — 需要 mingw-w64 工具链"
  [aarch64-linux-android]="Android ARM64 — 需要 Android NDK, 设置 ANDROID_NDK_HOME 环境变量"
  [aarch64-apple-ios]="iOS ARM64 — 需要 macOS + Xcode (iOS SDK), 仅限 Apple 平台"
)

# ─────────────────────────────────────────────────────────────────────────────
# 检查前置条件
# ─────────────────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════"
echo "  DevNote FFI — 安装跨编译目标"
echo "═══════════════════════════════════════════════════════════"
echo ""

if ! command -v rustup &>/dev/null; then
  echo "错误: rustup 未安装。请先安装 rustup:"
  echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 列出所有目标
# ─────────────────────────────────────────────────────────────────────────────
echo "需要安装的目标 (${#TARGETS[@]} 个):"
echo ""

for triple in "${TARGETS[@]}"; do
  echo "  • ${triple}"
  echo "    ${TARGET_NOTES[${triple}]}"
  echo ""
done

# ─────────────────────────────────────────────────────────────────────────────
# 安装每个目标
# ─────────────────────────────────────────────────────────────────────────────
echo "───────────────────────────────────────────────────────────"
echo "开始安装..."
echo "───────────────────────────────────────────────────────────"
echo ""

INSTALLED=0
SKIPPED=0
FAILED=0

for triple in "${TARGETS[@]}"; do
  # 检查是否已安装
  if rustup target list --installed 2>/dev/null | grep -q "^${triple}$"; then
    echo "[已安装] ${triple} — 跳过"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "[安装]   ${triple} ..."
  if rustup target add "${triple}"; then
    INSTALLED=$((INSTALLED + 1))
    echo "  → ${triple} 安装成功"
  else
    FAILED=$((FAILED + 1))
    echo "  ✗ ${triple} 安装失败 (可能需要额外依赖)"
  fi
  echo ""
done

# ─────────────────────────────────────────────────────────────────────────────
# 汇总
# ─────────────────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════"
echo "  安装汇总"
echo "═══════════════════════════════════════════════════════════"
echo "  新安装:  ${INSTALLED}"
echo "  已存在:  ${SKIPPED}"
echo "  失败:    ${FAILED}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 额外工具链提示
# ─────────────────────────────────────────────────────────────────────────────
echo "───────────────────────────────────────────────────────────"
echo "  额外工具链设置提醒"
echo "───────────────────────────────────────────────────────────"
echo ""

echo "▸ Windows (MinGW):"
echo "    Ubuntu/Debian:  sudo apt install gcc-mingw-w64"
echo "    macOS (Homebrew): brew install mingw-w64"
echo ""

echo "▸ Android NDK:"
echo "    1. 通过 Android Studio SDK Manager 安装 NDK (推荐版本 ≥ r26)"
echo "    2. 设置环境变量:"
echo '         export ANDROID_NDK_HOME="$HOME/Android/Sdk/ndk/<version>"'
echo "    3. 安装 cargo-ndk 可简化构建:"
echo "         cargo install cargo-ndk"
echo ""

echo "▸ iOS (Apple 平台专用):"
echo "    需要 macOS + Xcode Command Line Tools"
echo "    安装 Xcode CLI: xcode-select --install"
echo "    iOS 模拟器目标 (可选):"
echo "      rustup target add x86_64-apple-ios  # Intel 模拟器"
echo "      rustup target add aarch64-apple-ios-sim  # Apple Silicon 模拟器"
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "  完成!"
echo "═══════════════════════════════════════════════════════════"
