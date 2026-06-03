#!/bin/bash
# 测试基线 —— 建立 Rust/Go/Flutter 三层测试体系，确保架构变更不引入回归
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

run_step() {
    local name="$1"
    shift
    echo ""
    echo "=== 运行 $name 测试 ==="
    if "$@"; then
        echo "✓ $name 测试通过"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "✗ $name 测试失败"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

# ── Rust 测试 ──────────────────────────────────────────────────────────────
echo "=== Rust 测试 ==="
cd "$PROJECT_ROOT/rust-core"

if cargo test --workspace 2>&1; then
    echo "✓ Rust 测试通过"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "✗ Rust 测试失败"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ── Go 测试 ────────────────────────────────────────────────────────────────
echo ""
echo "=== Go 测试 ==="

run_step "Sync Server" bash -c "cd '$PROJECT_ROOT/sync-server' && go test ./..."

if [ -d "$PROJECT_ROOT/business-server" ]; then
    run_step "Business Server" bash -c "cd '$PROJECT_ROOT/business-server' && go test ./..."
fi

# ── Flutter 测试 ──────────────────────────────────────────────────────────
echo ""
echo "=== Flutter 测试 ==="

if command -v flutter &>/dev/null; then
    cd "$PROJECT_ROOT"
    if flutter test 2>&1; then
        echo "✓ Flutter 测试通过"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "✗ Flutter 测试失败"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "⚠ Flutter SDK 未安装，跳过 Flutter 测试"
fi

# ── 测试结果汇总 ──────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  测试结果汇总: $PASS_COUNT 通过, $FAIL_COUNT 失败"
echo "========================================="

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi

echo "=== 所有测试通过 ==="
exit 0