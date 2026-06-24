#!/bin/bash
# 测试基线 —— 建立 Rust/Go/Flutter 三层测试体系，确保架构变更不引入回归
#
# P0-3 修复: 与 GitHub Actions CI 工作流对齐，支持本地预检
#
# 此脚本在本地模拟 CI 流水线的核心检查项，开发者提交前可运行以预检:
#   - Rust: cargo test + cargo clippy + cargo fmt --check
#   - Go:   go test + go vet
#   - Flutter: flutter test + dart analyze
#
# FRB v2 迁移: Rust 集成测试已改为直接调用 frb_api.rs 中的 pub fn 函数，
# 替代原 C ABI dispatch 测试。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

run_step() {
    local name="$1"
    shift
    echo ""
    echo "=== 运行 $name ==="
    if "$@"; then
        echo "✓ $name 通过"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "✗ $name 失败"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ── Rust 测试 ──────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════"
echo "  Rust CI"
echo "═══════════════════════════════════════════"
cd "$PROJECT_ROOT/rust-core"

# 格式检查（CI 中为 cargo fmt --check）
if command -v rustfmt &>/dev/null; then
    run_step "Rust 格式检查 (cargo fmt --check)" \
        cargo fmt --all -- --check
else
    echo "⚠ rustfmt 未安装，跳过格式检查（运行 rustup component add rustfmt）"
fi

# Clippy 静态分析（CI 中拒绝 warning）
if cargo clippy --help &>/dev/null; then
    run_step "Rust Clippy 静态分析" \
        cargo clippy --workspace --all-targets -- -D warnings
else
    echo "⚠ clippy 不可用，跳过静态分析"
fi

# 单元测试与集成测试
run_step "Rust 测试 (cargo test --workspace)" \
    cargo test --workspace

# ── Go 测试 ────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  Go CI"
echo "═══════════════════════════════════════════"

if command -v go &>/dev/null; then
    # Sync Server
    if [ -d "$PROJECT_ROOT/sync-server" ]; then
        run_step "Sync Server 静态分析 (go vet)" \
            bash -c "cd '$PROJECT_ROOT/sync-server' && go vet ./..."
        run_step "Sync Server 测试 (go test)" \
            bash -c "cd '$PROJECT_ROOT/sync-server' && go test ./... -race"
    fi

    # Business Server
    if [ -d "$PROJECT_ROOT/business-server" ]; then
        run_step "Business Server 静态分析 (go vet)" \
            bash -c "cd '$PROJECT_ROOT/business-server' && go vet ./..."
        run_step "Business Server 测试 (go test)" \
            bash -c "cd '$PROJECT_ROOT/business-server' && go test ./... -race"
    fi
else
    echo "⚠ Go 未安装，跳过 Go 测试"
fi

# ── Flutter 测试 ──────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  Flutter CI"
echo "═══════════════════════════════════════════"

if command -v flutter &>/dev/null; then
    cd "$PROJECT_ROOT"

    # 依赖解析
    run_step "Flutter 依赖解析 (pub get)" \
        flutter pub get

    # 代码生成（确保 freezed/json_serializable 代码与源码同步）
    run_step "Flutter 代码生成 (build_runner)" \
        dart run build_runner build --delete-conflicting-outputs

    # 静态分析
    run_step "Flutter 静态分析 (dart analyze)" \
        dart analyze --fatal-infos

    # FRB codegen 生成的文件应已提交到仓库，无需每次测试时重新生成
    # 如需重新生成，运行: ./scripts/codegen.sh
    run_step "Flutter 测试 (flutter test)" \
        flutter test
else
    echo "⚠ Flutter SDK 未安装，跳过 Flutter 测试"
fi

# ── 测试结果汇总 ──────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  测试结果汇总: $PASS_COUNT 通过, $FAIL_COUNT 失败"
echo "═══════════════════════════════════════════"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi

echo "=== 所有检查通过 ==="
exit 0
