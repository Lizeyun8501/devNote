#!/usr/bin/env bash
###############################################################################
# codegen.sh — flutter_rust_bridge v2 代码生成脚本
#
# 用法:
#   ./codegen.sh [--watch]
#
# 此脚本生成 Dart ↔ Rust 类型安全绑定，替代手写 C ABI。
#
# 生成的文件:
#   Dart: lib/src/rust/frb_generated.dart, lib/src/rust/frb_generated.io.dart,
#          lib/src/rust/frb_generated.web.dart, lib/src/rust/library.dart
#   Rust:  rust-core/devnote-ffi/src/frb_generated.rs, rust-core/devnote-ffi/src/frb_generated.h
#
# 文档: https://cjycode.com/flutter_rust_bridge/
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

WATCH_MODE="false"
if [[ "${1:-}" == "--watch" ]]; then
  WATCH_MODE="true"
fi

# 检查 flutter_rust_bridge_codegen 是否可用
if ! command -v flutter_rust_bridge_codegen &>/dev/null; then
  echo "错误: flutter_rust_bridge_codegen 未安装"
  echo ""
  echo "安装方法:"
  echo "  flutter pub global activate flutter_rust_bridge_codegen"
  echo ""
  echo "或使用 Flutter 激活:"
  echo "  flutter pub global activate flutter_rust_bridge_codegen"
  exit 1
fi

cd "${PROJECT_ROOT}"

echo "═══════════════════════════════════════════════════════════"
echo "  flutter_rust_bridge v2 代码生成"
echo "═══════════════════════════════════════════════════════════"
echo "输入: rust-core/devnote-ffi/src/frb_api.rs"
echo "输出: lib/src/rust/ (Dart) + rust-core/devnote-ffi/src/ (Rust)"
echo "═══════════════════════════════════════════════════════════"
echo ""

if [[ "${WATCH_MODE}" == "true" ]]; then
  echo "[模式] Watch 模式 - 文件变更时自动重新生成"
  echo ""
  flutter_rust_bridge_codegen generate --watch
else
  flutter_rust_bridge_codegen generate
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  代码生成完成!"
echo ""
echo "生成的 Dart 文件:"
echo "  - lib/src/rust/frb_generated.dart"
echo "  - lib/src/rust/frb_generated.io.dart"
echo "  - lib/src/rust/frb_generated.web.dart"
echo "  - lib/src/rust/library.dart"
echo ""
echo "生成的 Rust 文件:"
echo "  - rust-core/devnote-ffi/src/frb_generated.rs"
echo "  - rust-core/devnote-ffi/src/frb_generated.h"
echo "═══════════════════════════════════════════════════════════"
