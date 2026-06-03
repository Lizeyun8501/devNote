#!/usr/bin/env bash
###############################################################################
# build_rust.sh — 跨平台 FFI 构建脚本 (DevNote Rust Library)
#
# 用法:
#   ./build_rust.sh [--target <platform>] [--release|--debug] [--output-dir <dir>]
#
# 支持的平台:
#   linux-x86_64   macos-x86_64   macos-aarch64
#   windows-x86_64 android-arm64   ios-aarch64
###############################################################################
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# 常量定义
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUST_CORE_DIR="${PROJECT_ROOT}/rust-core"
FFI_PACKAGE="devnote-ffi"

# 默认参数
TARGET=""
RELEASE_MODE="true"
OUTPUT_DIR="rust-ffi-libs"

# ─────────────────────────────────────────────────────────────────────────────
# 平台 → Cargo target triple 映射
# ─────────────────────────────────────────────────────────────────────────────
declare -A TARGET_TRIPLES=(
  [linux-x86_64]="x86_64-unknown-linux-gnu"
  [macos-x86_64]="x86_64-apple-darwin"
  [macos-aarch64]="aarch64-apple-darwin"
  [windows-x86_64]="x86_64-pc-windows-gnu"
  [android-arm64]="aarch64-linux-android"
  [ios-aarch64]="aarch64-apple-ios"
)

# ─────────────────────────────────────────────────────────────────────────────
# 平台 → 输出文件名映射
# ─────────────────────────────────────────────────────────────────────────────
declare -A LIB_NAMES=(
  [linux-x86_64]="libdevnote_ffi.so"
  [macos-x86_64]="libdevnote_ffi.dylib"
  [macos-aarch64]="libdevnote_ffi.dylib"
  [windows-x86_64]="devnote_ffi.dll"
  [android-arm64]="libdevnote_ffi.so"
  [ios-aarch64]="libdevnote_ffi.a"
)

# ─────────────────────────────────────────────────────────────────────────────
# 辅助函数
# ─────────────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
用法: $(basename "$0") [选项]

选项:
  --target <platform>   目标平台 (默认: 当前主机平台)
                        可选: linux-x86_64 macos-x86_64 macos-aarch64
                              windows-x86_64 android-arm64 ios-aarch64
  --release             以 Release 模式构建 (默认)
  --debug               以 Debug 模式构建
  --output-dir <dir>    输出目录 (默认: rust-ffi-libs/)
  -h, --help            显示帮助信息
EOF
  exit 0
}

# 自动检测当前主机平台
detect_host_platform() {
  local os
  os="$(uname -s)"
  local arch
  arch="$(uname -m)"

  case "${os}" in
    Linux)
      echo "linux-x86_64"
      ;;
    Darwin)
      if [[ "${arch}" == "arm64" ]]; then
        echo "macos-aarch64"
      else
        echo "macos-x86_64"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "windows-x86_64"
      ;;
    *)
      echo ""
      ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# 参数解析
# ─────────────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="$2"
      shift 2
      ;;
    --release)
      RELEASE_MODE="true"
      shift
      ;;
    --debug)
      RELEASE_MODE="false"
      shift
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "错误: 未知参数 '$1'"
      echo ""
      usage
      ;;
  esac
done

# 如果未指定目标, 自动检测
if [[ -z "${TARGET}" ]]; then
  TARGET="$(detect_host_platform)"
  if [[ -z "${TARGET}" ]]; then
    echo "错误: 无法自动检测当前平台, 请使用 --target 参数指定"
    exit 1
  fi
  echo "[信息] 未指定 --target, 自动检测为: ${TARGET}"
fi

# 验证目标平台是否合法
if [[ -z "${TARGET_TRIPLES[${TARGET}]+x}" ]]; then
  echo "错误: 不支持的目标平台 '${TARGET}'"
  echo "支持的平台: ${!TARGET_TRIPLES[*]}"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 构建流程
# ─────────────────────────────────────────────────────────────────────────────
TRIPLE="${TARGET_TRIPLES[${TARGET}]}"
LIB_NAME="${LIB_NAMES[${TARGET}]}"

if [[ "${RELEASE_MODE}" == "true" ]]; then
  CARGO_PROFILE="release"
  CARGO_MODE_ARGS="--release"
else
  CARGO_PROFILE="debug"
  CARGO_MODE_ARGS=""
fi

echo "═══════════════════════════════════════════════════════════"
echo "  DevNote FFI 跨平台构建"
echo "═══════════════════════════════════════════════════════════"
echo "[1/4] 目标平台:   ${TARGET}"
echo "       Target:    ${TRIPLE}"
echo "[2/4] 构建模式:   ${CARGO_PROFILE}"
echo "[3/4] 输出目录:   ${OUTPUT_DIR}/${TARGET}/"
echo "       产物名称:   ${LIB_NAME}"
echo "═══════════════════════════════════════════════════════════"
echo ""

# 检查 cargo 是否可用
if ! command -v cargo &>/dev/null; then
  echo "错误: cargo 未安装或不在 PATH 中"
  exit 1
fi

# 创建输出目录
PLATFORM_OUTPUT_DIR="${OUTPUT_DIR}/${TARGET}"
echo "[步骤 1/3] 创建输出目录: ${PLATFORM_OUTPUT_DIR}"
mkdir -p "${PLATFORM_OUTPUT_DIR}"

# 执行 cargo build
echo "[步骤 2/3] 编译 ${FFI_PACKAGE} (target: ${TRIPLE})..."
cd "${RUST_CORE_DIR}"
cargo build -p "${FFI_PACKAGE}" --target "${TRIPLE}" ${CARGO_MODE_ARGS}

# 定位构建产物
CARGO_TARGET_DIR="${RUST_CORE_DIR}/target/${TRIPLE}/${CARGO_PROFILE}"
SOURCE_LIB="${CARGO_TARGET_DIR}/${LIB_NAME}"

if [[ ! -f "${SOURCE_LIB}" ]]; then
  echo "错误: 构建产物未找到: ${SOURCE_LIB}"
  echo "请检查构建是否成功以及产物名称是否正确"
  exit 1
fi

# 复制产物到输出目录
echo "[步骤 3/3] 复制产物 → ${PLATFORM_OUTPUT_DIR}/${LIB_NAME}"
cp "${SOURCE_LIB}" "${PLATFORM_OUTPUT_DIR}/${LIB_NAME}"

# 打印产物信息
LIB_SIZE="$(du -h "${PLATFORM_OUTPUT_DIR}/${LIB_NAME}" | cut -f1)"
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  构建完成!"
echo "  平台:     ${TARGET}"
echo "  文件:     ${PLATFORM_OUTPUT_DIR}/${LIB_NAME}"
echo "  大小:     ${LIB_SIZE}"
echo "═══════════════════════════════════════════════════════════"
