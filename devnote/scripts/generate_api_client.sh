#!/usr/bin/env bash
# ============================================================
# DevNote API 客户端代码生成脚本
# P2-9: OpenAPI 契约驱动 Dart 客户端生成
#
# 依赖: Java 17+ (openapi-generator-cli 需要 JVM)
# 用法: ./scripts/generate_api_client.sh [sync|business|all]
# 默认: all
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPEC_DIR="$PROJECT_ROOT/docs/api"
OUTPUT_BASE="$PROJECT_ROOT/lib/api/generated"
CONFIG_FILE="$PROJECT_ROOT/openapi-generator-config.yaml"

TARGET="${1:-all}"

generate_client() {
  local name="$1"
  local spec="$2"
  local output="$OUTPUT_BASE/$name"
  local pub_name="$3"

  echo ">>> 生成 $name 客户端..."
  echo "    spec:     $spec"
  echo "    output:   $output"
  echo "    pubName:  $pub_name"

  # 使用 npx 运行 openapi-generator-cli（自动下载 JAR）
  # pubName: pubspec.yaml 包名；pubLibrary: Dart library 名称（避免 sed 修正）
  npx @openapitools/openapi-generator-cli generate \
    -i "$spec" \
    -g dart \
    -o "$output" \
    -c "$CONFIG_FILE" \
    -p "pubName=$pub_name" \
    -p "pubLibrary=$pub_name" \
    --skip-validate-spec

  echo ">>> $name 客户端生成完成"
  echo "    生成位置: $output"

  # 安全网：确保 library/part of 声明与 pubName 一致
  # （openapi-generator 某些版本 pubLibrary 不生效，需手动修正）
  find "$output/lib" -name "*.dart" -exec sed -i \
    -e "s/library devnote_api;/library $pub_name;/g" \
    -e "s/part of devnote_api;/part of $pub_name;/g" \
    {} +
  echo "    library 名称已修正为 $pub_name"
  echo ""
}

case "$TARGET" in
  sync)
    generate_client "sync_server" "$SPEC_DIR/sync-server-openapi.yaml" "devnote_sync_api"
    ;;
  business)
    generate_client "business_server" "$SPEC_DIR/business-server-openapi.yaml" "devnote_business_api"
    ;;
  all)
    generate_client "sync_server" "$SPEC_DIR/sync-server-openapi.yaml" "devnote_sync_api"
    generate_client "business_server" "$SPEC_DIR/business-server-openapi.yaml" "devnote_business_api"
    ;;
  *)
    echo "用法: $0 [sync|business|all]"
    exit 1
    ;;
esac

echo "============================================================"
echo "代码生成完成。"
echo ""
echo "下一步:"
echo "  1. 检查 lib/api/generated/ 下的生成代码"
echo "  2. 通过 lib/api/devnote_api_client.dart 统一封装使用"
echo "  3. 逐步将手写 HTTP 调用迁移到生成的 API 客户端"
echo "============================================================"
