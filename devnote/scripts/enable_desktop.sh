#!/bin/bash
# 启用桌面端支持
# 借鉴 AppFlowy 的全平台策略 —— Flutter 一套代码覆盖 6 个平台
#
# 使用方法: ./scripts/enable_desktop.sh
#
# 此脚本运行 flutter create 为现有项目添加桌面端平台支持

set -e

echo "=== DevNote 桌面端启用脚本 ==="
echo ""

# 检查 Flutter 是否安装
if ! command -v flutter &> /dev/null; then
    echo "错误: Flutter 未安装。请先安装 Flutter SDK。"
    exit 1
fi

echo "1. 为项目添加桌面端平台支持..."
flutter create --platforms=macos,windows,linux .

echo ""
echo "2. 桌面端平台支持已添加。"
echo ""
echo "下一步:"
echo "  - macOS:   flutter run -d macos"
echo "  - Windows: flutter run -d windows"
echo "  - Linux:   flutter run -d linux"
echo ""
echo "构建发布版本:"
echo "  - macOS:   flutter build macos"
echo "  - Windows: flutter build windows"
echo "  - Linux:   flutter build linux"
